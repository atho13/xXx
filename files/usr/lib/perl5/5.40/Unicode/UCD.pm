package Unicode::UCD;

use strict;
use warnings;
no warnings 'surrogate';    # surrogates can be inputs to this
use charnames ();

our $VERSION = '0.78';

sub DEBUG () { 0 }
$|=1 if DEBUG;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(charinfo
		    charblock charscript
		    charblocks charscripts
		    charinrange
		    charprop
		    charprops_all
		    general_categories bidi_types
		    compexcl
		    casefold all_casefolds casespec
		    namedseq
                    num
                    prop_aliases
                    prop_value_aliases
                    prop_values
                    prop_invlist
                    prop_invmap
                    search_invlist
                    MAX_CP
                );

use Carp;

sub IS_ASCII_PLATFORM { ord("A") == 65 }


our %caseless_equivalent;
our $e_precision;
our %file_to_swash_name;
our @inline_definitions;
our %loose_property_name_of;
our %loose_property_to_file_of;
our %loose_to_file_of;
our $MAX_CP;
our %nv_floating_to_rational;
our %prop_aliases;
our %stricter_to_file_of;
our %strict_property_to_file_of;
our %SwashInfo;
our %why_deprecated;

my $v_unicode_version;  # v-string.

sub openunicode {
    my (@path) = @_;
    my $rfh;
    for my $d (@INC) {
        use File::Spec;
        my $f = File::Spec->catfile($d, "unicore", @path);
        return $rfh if open($rfh, '<', $f);
    }
    croak __PACKAGE__, ": failed to find ",
        File::Spec->catfile("unicore", @path), " in @INC";
}

sub _dclone ($) {   # Use Storable::dclone if available; otherwise emulate it.

    use if defined &DynaLoader::boot_DynaLoader, Storable => qw(dclone);

    return dclone(shift) if defined &dclone;

    my $arg = shift;
    my $type = ref $arg;
    return $arg unless $type;   # No deep cloning needed for scalars

    if ($type eq 'ARRAY') {
        my @return;
        foreach my $element (@$arg) {
            push @return, &_dclone($element);
        }
        return \@return;
    }
    elsif ($type eq 'HASH') {
        my %return;
        foreach my $key (keys %$arg) {
            $return{$key} = &_dclone($arg->{$key});
        }
        return \%return;
    }
    else {
        croak "_dclone can't handle " . $type;
    }
}


my %Cache;

my $digits = qr/ ( [0-9] _? )+ (?!:_) /x;

my $sign = qr/ \s* [+-]? \s* /x;

my $f_float = qr/  $sign $digits+ \. $digits*    # e.g., 5.0, 5.
                 | $sign $digits* \. $digits+/x; # 0.7, .7

my $number = qr{  ^ $sign $digits+ $
                | ^ $sign $digits+ \/ $sign $digits+ $
                | ^ $f_float (?: [Ee] [+-]? $digits )? $}x;

sub loose_name ($) {
    # Given a lowercase property or property-value name, return its
    # standardized version that is expected for look-up in the 'loose' hashes
    # in UCD.pl (hence, this depends on what mktables does).  This squeezes
    # out blanks, underscores and dashes.  The complication stems from the
    # grandfathered-in 'L_', which retains a single trailing underscore.

my $integer_or_float_re = qr/ ^ -? \d+ (:? \. \d+ )? $ /x;

my $numeric_re = qr! $integer_or_float_re | ^ -? \d+ / \d+ $ !x;
    return $_[0] if $_[0] =~ $numeric_re;

    (my $loose = $_[0]) =~ s/[-_ \t]//g;

    return $loose if $loose !~ / ^ (?: is | to )? l $/x;
    return 'l_' if $_[0] =~ / l .* _ /x;    # If original had a trailing '_'
    return $loose;
}


{
    use re "/aa";  # Nothing here uses above Latin1.

    # If a floating point number is within this distance from the value of a
    # fraction, it is considered to be that fraction, even if many more digits
    # are specified that don't exactly match.
    my $min_floating_slop;

    # To guard against this program calling something that in turn ends up
    # calling this program with the same inputs, and hence infinitely
    # recursing, we keep a stack of the properties that are currently in
    # progress, pushed upon entry, popped upon return.
    my @recursed;

    sub SWASHNEW {
        my ($class, $type, $list, $minbits) = @_;
        my $user_defined = 0;
        local $^D = 0 if $^D;

        $class = "" unless defined $class;
        print STDERR __LINE__, ": class=$class, type=$type, list=",
                                (defined $list) ? $list : ':undef:',
                                ", minbits=$minbits\n" if DEBUG;

        ##
        ## Get the list of codepoints for the type.
        ## Called from swash_init (see utf8.c) or SWASHNEW itself.
        ##
        ## Callers of swash_init:
        ##     prop_invlist
        ##     Unicode::UCD::prop_invmap
        ##
        ## Given a $type, our goal is to fill $list with the set of codepoint
        ## ranges. If $type is false, $list passed is used.
        ##
        ## $minbits:
        ##     For binary properties, $minbits must be 1.
        ##     For character mappings (case and transliteration), $minbits must
        ##     be a number except 1.
        ##
        ## $list (or that filled according to $type):
        ##     Refer to perlunicode.pod, "User-Defined Character Properties."
        ##
        ##     For binary properties, only characters with the property value
        ##     of True should be listed. The 3rd column, if any, will be ignored
        ##
        ## To make the parsing of $type clear, this code takes the a rather
        ## unorthodox approach of last'ing out of the block once we have the
        ## info we need. Were this to be a subroutine, the 'last' would just
        ## be a 'return'.
        ##
        #   If a problem is found $type is returned;
        #   Upon success, a new (or cached) blessed object is returned with
        #   keys TYPE, BITS, EXTRAS, LIST, and with values having the
        #   same meanings as the input parameters.
        #   SPECIALS contains a reference to any special-treatment hash in the
        #       property.
        #   INVERT_IT is non-zero if the result should be inverted before use
        #   USER_DEFINED is non-zero if the result came from a user-defined
        my $file; ## file to load data from, and also part of the %Cache key.

        # Change this to get a different set of Unicode tables
        my $unicore_dir = 'unicore';
        my $invert_it = 0;
        my $list_is_from_mktables = 0;  # Is $list returned from a mktables
                                        # generated file?  If so, we know it's
                                        # well behaved.

        if ($type)
        {
            # Verify that this isn't a recursive call for this property.
            # Can't use croak, as it may try to recurse to here itself.
            my $class_type = $class . "::$type";
            if (grep { $_ eq $class_type } @recursed) {
                CORE::die "panic: Infinite recursion in SWASHNEW for '$type'\n";
            }
            push @recursed, $class_type;

            $type =~ s/^\s+//;
            $type =~ s/\s+$//;

            # regcomp.c surrounds the property name with '__" and '_i' if this
            # is to be caseless matching.
            my $caseless = $type =~ s/^(.*)__(.*)_i$/$1$2/;

            print STDERR __LINE__, ": type=$type, caseless=$caseless\n" if DEBUG;

        GETFILE:
            {
                ##
                ## It could be a user-defined property.  Look in current
                ## package if no package given
                ##


                my $caller0 = caller(0);
                my $caller1 = $type =~ s/(.+):://
                              ? $1
                              : $caller0 eq 'main'
                                ? 'main'
                                : caller(1);

                if (defined $caller1 && $type =~ /^I[ns]\w+$/) {
                    my $prop = "${caller1}::$type";
                    if (exists &{$prop}) {
                        # stolen from Scalar::Util::PP::tainted()
                        my $tainted;
                        {
                            local($@, $SIG{__DIE__}, $SIG{__WARN__});
                            local $^W = 0;
                            no warnings;
                            eval { kill 0 * $prop };
                            $tainted = 1 if $@ =~ /^Insecure/;
                        }
                        die "Insecure user-defined property \\p{$prop}\n"
                            if $tainted;
                        no strict 'refs';
                        $list = &{$prop}($caseless);
                        $user_defined = 1;
                        last GETFILE;
                    }
                }

                require "$unicore_dir/UCD.pl";

                # All property names are matched caselessly
                my $property_and_table = CORE::lc $type;
                print STDERR __LINE__, ": $property_and_table\n" if DEBUG;

                # See if is of the compound form 'property=value', where the
                # value indicates the table we should use.
                my ($property, $table, @remainder) =
                                    split /\s*[:=]\s*/, $property_and_table, -1;
                if (@remainder) {
                    pop @recursed if @recursed;
                    return $type;
                }

                my $prefix;
                if (! defined $table) {

                    # Here, is the single form.  The property becomes empty, and
                    # the whole value is the table.
                    $table = $property;
                    $prefix = $property = "";
                } else {
                    print STDERR __LINE__, ": $property\n" if DEBUG;

                    # Here it is the compound property=table form.  The property
                    # name is always loosely matched, and always can have an
                    # optional 'is' prefix (which isn't true in the single
                    # form).
                    $property = loose_name($property) =~ s/^is//r;

                    # And convert to canonical form.  Quit if not valid.
                    $property = $loose_property_name_of{$property};
                    if (! defined $property) {
                        pop @recursed if @recursed;
                        return $type;
                    }

                    $prefix = "$property=";

                    # If the rhs looks like it is a number...
                    print STDERR __LINE__, ": table=$table\n" if DEBUG;

                    if ($table =~ $number) {
                        print STDERR __LINE__, ": table=$table\n" if DEBUG;

                        # Split on slash, in case it is a rational, like \p{1/5}
                        my @parts = split m{ \s* / \s* }x, $table, -1;
                        print __LINE__, ": $type\n" if @parts > 2 && DEBUG;

                        foreach my $part (@parts) {
                            print __LINE__, ": part=$part\n" if DEBUG;

                            $part =~ s/^\+\s*//;    # Remove leading plus
                            $part =~ s/^-\s*/-/;    # Remove blanks after unary
                                                    # minus

                            # Remove underscores between digits.
                            $part =~ s/(?<= [0-9] ) _ (?= [0-9] ) //xg;

                            # No leading zeros (but don't make a single '0'
                            # into a null string)
                            $part =~ s/ ^ ( -? ) 0+ /$1/x;
                            $part .= '0' if $part eq '-' || $part eq "";

                            # No trailing zeros after a decimal point
                            $part =~ s/ ( \. [0-9]*? ) 0+ $ /$1/x;

                            # Begin with a 0 if a leading decimal point
                            $part =~ s/ ^ ( -? ) \. /${1}0./x;

                            # Ensure not a trailing decimal point: turn into an
                            # integer
                            $part =~ s/ \. $ //x;

                            print STDERR __LINE__, ": part=$part\n" if DEBUG;
                            #return $type if $part eq "";
                        }

                        #  If a rational...
                        if (@parts == 2) {

                            # If denominator is negative, get rid of it, and ...
                            if ($parts[1] =~ s/^-//) {

                                # If numerator is also negative, convert the
                                # whole thing to positive, else move the minus
                                # to the numerator
                                if ($parts[0] !~ s/^-//) {
                                    $parts[0] = '-' . $parts[0];
                                }
                            }
                            $table = join '/', @parts;
                        }
                        elsif ($property ne 'nv' || $parts[0] !~ /\./) {

                            # Here is not numeric value, or doesn't have a
                            # decimal point.  No further manipulation is
                            # necessary.  (Note the hard-coded property name.
                            # This could fail if other properties eventually
                            # had fractions as well; perhaps the cjk ones
                            # could evolve to do that.  This hard-coding could
                            # be fixed by mktables generating a list of
                            # properties that could have fractions.)
                            $table = $parts[0];
                        } else {

                            # Here is a floating point numeric_value.  Convert
                            # to rational.  Get a normalized form, like
                            # 5.00E-01, and look that up in the hash

                            my $float = sprintf "%.*e",
                                                $e_precision,
                                                0 + $parts[0];

                            if (exists $nv_floating_to_rational{$float}) {
                                $table = $nv_floating_to_rational{$float};
                            } else {
                                pop @recursed if @recursed;
                                return $type;
                            }
                        }
                        print STDERR __LINE__, ": $property=$table\n" if DEBUG;
                    }
                }

                # Combine lhs (if any) and rhs to get something that matches
                # the syntax of the lookups.
                $property_and_table = "$prefix$table";
                print STDERR __LINE__, ": $property_and_table\n" if DEBUG;

                # First try stricter matching.
                $file = $stricter_to_file_of{$property_and_table};

                # If didn't find it, try again with looser matching by editing
                # out the applicable characters on the rhs and looking up
                # again.
                my $strict_property_and_table;
                if (! defined $file) {

                    # This isn't used unless the name begins with 'to'
                    $strict_property_and_table = $property_and_table =~  s/^to//r;
                    $table = loose_name($table);
                    $property_and_table = "$prefix$table";
                    print STDERR __LINE__, ": $property_and_table\n" if DEBUG;
                    $file = $loose_to_file_of{$property_and_table};
                    print STDERR __LINE__, ": $property_and_table\n" if DEBUG;
                }

                # Add the constant and go fetch it in.
                if (defined $file) {

                    # If the file name contains a !, it means to invert.  The
                    # 0+ makes sure result is numeric
                    $invert_it = 0 + $file =~ s/!//;

                    if ($caseless
                        && exists $caseless_equivalent{$property_and_table})
                    {
                        $file = $caseless_equivalent{$property_and_table};
                    }

                    # The pseudo-directory '#' means that there really isn't a
                    # file to read, the data is in-line as part of the string;
                    # we extract it below.
                    $file = "$unicore_dir/lib/$file.pl" unless $file =~ m!^#/!;
                    last GETFILE;
                }
                print STDERR __LINE__, ": didn't find $property_and_table\n" if DEBUG;

                ##
                ## Last attempt -- see if it's a standard "To" name
                ## (e.g. "ToLower")  ToTitle is used by ucfirst().
                ## The user-level way to access ToDigit() and ToFold()
                ## is to use Unicode::UCD.
                ##
                # Only check if caller wants non-binary
                if ($minbits != 1) {
                    if ($property_and_table =~ s/^to//) {
                    # Look input up in list of properties for which we have
                    # mapping files.  First do it with the strict approach
                        if (defined ($file = $strict_property_to_file_of{
                                                    $strict_property_and_table}))
                        {
                            $type = $file_to_swash_name{$file};
                            print STDERR __LINE__, ": type set to $type\n"
                                                                        if DEBUG;
                            $file = "$unicore_dir/$file.pl";
                            last GETFILE;
                        }
                        elsif (defined ($file =
                          $loose_property_to_file_of{$property_and_table}))
                        {
                            $type = $file_to_swash_name{$file};
                            print STDERR __LINE__, ": type set to $type\n"
                                                                        if DEBUG;
                            $file = "$unicore_dir/$file.pl";
                            last GETFILE;
                        }   # If that fails see if there is a corresponding binary
                            # property file
                        elsif (defined ($file =
                                    $loose_to_file_of{$property_and_table}))
                        {

                            # Here, there is no map file for the property we
                            # are trying to get the map of, but this is a
                            # binary property, and there is a file for it that
                            # can easily be translated to a mapping, so use
                            # that, treating this as a binary property.
                            # Setting 'minbits' here causes it to be stored as
                            # such in the cache, so if someone comes along
                            # later looking for just a binary, they get it.
                            $minbits = 1;

                            # The 0+ makes sure is numeric
                            $invert_it = 0 + $file =~ s/!//;
                            $file = "$unicore_dir/lib/$file.pl"
                                                         unless $file =~ m!^#/!;
                            last GETFILE;
                        }
                    }
                }

                ##
                ## If we reach this line, it's because we couldn't figure
                ## out what to do with $type. Ouch.
                ##

                pop @recursed if @recursed;
                return $type;
            } # end of GETFILE block

            if (defined $file) {
                print STDERR __LINE__, ": found it (file='$file')\n" if DEBUG;

                ##
                ## If we reach here, it was due to a 'last GETFILE' above
                ## (exception: user-defined properties and mappings), so we
                ## have a filename, so now we load it if we haven't already.

                # The pseudo-directory '#' means the result isn't really a
                # file, but is in-line, with semi-colons to be turned into
                # new-lines.  Since it is in-line there is no advantage to
                # caching the result
                if ($file =~ s!^#/!!) {
                    $list = $inline_definitions[$file];
                }
                else {
                    # Here, we have an actual file to read in and load, but it
                    # may already have been read-in and cached.  The cache key
                    # is the class and file to load, and whether the results
                    # need to be inverted.
                    my $found = $Cache{$class, $file, $invert_it};
                    if ($found and ref($found) eq $class) {
                        print STDERR __LINE__, ": Returning cached swash for '$class,$file,$invert_it' for \\p{$type}\n" if DEBUG;
                        pop @recursed if @recursed;
                        return $found;
                    }

                    local $@;
                    local $!;
                    $list = do $file; die $@ if $@;
                }

                $list_is_from_mktables = 1;
            }
        } # End of $type is non-null

        # Here, either $type was null, or we found the requested property and
        # read it into $list

        my $extras = "";

        my $bits = $minbits;

        # mktables lists don't have extras, like '&prop', so don't need
        # to separate them; also lists are already sorted, so don't need to do
        # that.
        if ($list && ! $list_is_from_mktables) {
            my $taint = substr($list,0,0); # maintain taint

            # Separate the extras from the code point list, and make sure
            # user-defined properties are well-behaved for
            # downstream code.
            if ($user_defined) {
                my @tmp = split(/^/m, $list);
                my %seen;
                no warnings;

                # The extras are anything that doesn't begin with a hex digit.
                $extras = join '', $taint, grep /^[^0-9a-fA-F]/, @tmp;

                # Remove the extras, and sort the remaining entries by the
                # numeric value of their beginning hex digits, removing any
                # duplicates.
                $list = join '', $taint,
                        map  { $_->[1] }
                        sort { $a->[0] <=> $b->[0] }
                        map  { /^([0-9a-fA-F]+)/ && !$seen{$1}++ ? [ CORE::hex($1), $_ ] : () }
                        @tmp; # XXX doesn't do ranges right
            }
            else {
                # mktables has gone to some trouble to make non-user defined
                # properties well-behaved, so we can skip the effort we do for
                # user-defined ones.  Any extras are at the very beginning of
                # the string.

                # This regex splits out the first lines of $list into $1 and
                # strips them off from $list, until we get one that begins
                # with a hex number, alone on the line, or followed by a tab.
                # Either portion may be empty.
                $list =~ s/ \A ( .*? )
                            (?: \z | (?= ^ [0-9a-fA-F]+ (?: \t | $) ) )
                          //msx;

                $extras = "$taint$1";
            }
        }

        if ($minbits != 1 && $minbits < 32) { # not binary property
            my $top = 0;
            while ($list =~ /^([0-9a-fA-F]+)(?:[\t]([0-9a-fA-F]+)?)(?:[ \t]([0-9a-fA-F]+))?/mg) {
                my $min = CORE::hex $1;
                my $max = defined $2 ? CORE::hex $2 : $min;
                my $val = defined $3 ? CORE::hex $3 : 0;
                $val += $max - $min if defined $3;
                $top = $val if $val > $top;
            }
            my $topbits =
                $top > 0xffff ? 32 :
                $top > 0xff ? 16 : 8;
            $bits = $topbits if $bits < $topbits;
        }

        my @extras;
        if ($extras) {
            for my $x ($extras) {
                my $taint = substr($x,0,0); # maintain taint
                pos $x = 0;
                while ($x =~ /^([^0-9a-fA-F\n])(.*)/mg) {
                    my $char = "$1$taint";
                    my $name = "$2$taint";
                    print STDERR __LINE__, ": char [$char] => name [$name]\n"
                        if DEBUG;
                    if ($char =~ /[-+!&]/) {
                        my ($c,$t) = split(/::/, $name, 2);	# bogus use of ::, really
                        my $subobj;
                        if ($c eq 'utf8') { # khw is unsure of this
                            $subobj = SWASHNEW($t, "", $minbits, 0);
                        }
                        elsif (exists &$name) {
                            $subobj = SWASHNEW($name, "", $minbits, 0);
                        }
                        elsif ($c =~ /^([0-9a-fA-F]+)/) {
                            $subobj = SWASHNEW("", $c, $minbits, 0);
                        }
                        print STDERR __LINE__, ": returned from getting sub object for $name\n" if DEBUG;
                        if (! ref $subobj) {
                            pop @recursed if @recursed && $type;
                            return $subobj;
                        }
                        push @extras, $name => $subobj;
                        $bits = $subobj->{BITS} if $bits < $subobj->{BITS};
                        $user_defined = $subobj->{USER_DEFINED}
                                              if $subobj->{USER_DEFINED};
                    }
                }
            }
        }

        if (DEBUG) {
            print STDERR __LINE__, ": CLASS = $class, TYPE => $type, BITS => $bits, INVERT_IT => $invert_it, USER_DEFINED => $user_defined";
            print STDERR "\nLIST =>\n$list" if defined $list;
            print STDERR "\nEXTRAS =>\n$extras" if defined $extras;
            print STDERR "\n";
        }

        my $SWASH = bless {
            TYPE => $type,
            BITS => $bits,
            EXTRAS => $extras,
            LIST => $list,
            USER_DEFINED => $user_defined,
            @extras,
        } => $class;

        if ($file) {
            $Cache{$class, $file, $invert_it} = $SWASH;
            if ($type
                && exists $SwashInfo{$type}
                && exists $SwashInfo{$type}{'specials_name'})
            {
                my $specials_name = $SwashInfo{$type}{'specials_name'};
                no strict "refs";
                print STDERR "\nspecials_name => $specials_name\n" if DEBUG;
                $SWASH->{'SPECIALS'} = \%$specials_name;
            }
            $SWASH->{'INVERT_IT'} = $invert_it;
        }

        pop @recursed if @recursed && $type;

        return $SWASH;
    }
}

sub _getcode {
    my $arg = shift;

    if ($arg =~ /^[1-9]\d*$/) {
	return $arg;
    }
    elsif ($arg =~ /^(?:0[xX])?([[:xdigit:]]+)$/) {
	return CORE::hex($1);
    }
    elsif ($arg =~ /^[Uu]\+([[:xdigit:]]+)$/) { # Is of form U+0000, means
                                                # wants the Unicode code
                                                # point, not the native one
        my $decimal = CORE::hex($1);
        return $decimal if IS_ASCII_PLATFORM;
        return utf8::unicode_to_native($decimal);
    }

    return;
}

my %real_to_rational;

my @BIDIS;
my @CATEGORIES;
my @DECOMPOSITIONS;
my @NUMERIC_TYPES;
my %SIMPLE_LOWER;
my %SIMPLE_TITLE;
my %SIMPLE_UPPER;
my %UNICODE_1_NAMES;
my %ISO_COMMENT;

my $Hangul_Syllables_re = eval 'qr/\p{Block=Hangul_Syllables}/';

sub charinfo {

    # This function has traditionally mimicked what is in UnicodeData.txt,
    # warts and all.  This is a re-write that avoids UnicodeData.txt so that
    # it can be removed to save disk space.  Instead, this assembles
    # information gotten by other methods that get data from various other
    # files.  It uses charnames to get the character name; and various
    # mktables tables.

    use feature 'unicode_strings';

    # Will fail if called under minitest
    use if defined &DynaLoader::boot_DynaLoader, "Unicode::Normalize" => qw(getCombinClass NFD);

    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::charinfo: unknown code '$arg'" unless defined $code;

    # Non-unicode implies undef.
    return if $code > 0x10FFFF;

    my %prop;
    my $char = chr($code);

    @CATEGORIES =_read_table("To/Gc.pl") unless @CATEGORIES;
    $prop{'category'} = _search(\@CATEGORIES, 0, $#CATEGORIES, $code)
                        // $SwashInfo{'ToGc'}{'missing'};
    # Return undef if category value is 'Unassigned' or one of its synonyms
    return if grep { lc $_ eq 'unassigned' }
                                    prop_value_aliases('Gc', $prop{'category'});

    $prop{'code'} = sprintf "%04X", $code;
    $prop{'name'} = ($char =~ /\p{Cntrl}/) ? '<control>'
                                           : (charnames::viacode($code) // "");

    $prop{'combining'} = getCombinClass($code);

    @BIDIS =_read_table("To/Bc.pl") unless @BIDIS;
    $prop{'bidi'} = _search(\@BIDIS, 0, $#BIDIS, $code)
                    // $SwashInfo{'ToBc'}{'missing'};

    # For most code points, we can just read in "unicore/Decomposition.pl", as
    # its contents are exactly what should be output.  But that file doesn't
    # contain the data for the Hangul syllable decompositions, which can be
    # algorithmically computed, and NFD() does that, so we call NFD() for
    # those.  We can't use NFD() for everything, as it does a complete
    # recursive decomposition, and what this function has always done is to
    # return what's in UnicodeData.txt which doesn't show that recursiveness.
    # Fortunately, the NFD() of the Hanguls doesn't have any recursion
    # issues.
    # Having no decomposition implies an empty field; otherwise, all but
    # "Canonical" imply a compatible decomposition, and the type is prefixed
    # to that, as it is in UnicodeData.txt
    UnicodeVersion() unless defined $v_unicode_version;
    if ($v_unicode_version ge v2.0.0 && $char =~ $Hangul_Syllables_re) {
        # The code points of the decomposition are output in standard Unicode
        # hex format, separated by blanks.
        $prop{'decomposition'} = join " ", map { sprintf("%04X", $_)}
                                           unpack "U*", NFD($char);
    }
    else {
        @DECOMPOSITIONS = _read_table("Decomposition.pl")
                          unless @DECOMPOSITIONS;
        $prop{'decomposition'} = _search(\@DECOMPOSITIONS, 0, $#DECOMPOSITIONS,
                                                                $code) // "";
    }

    # Can use num() to get the numeric values, if any.
    if (! defined (my $value = num($char))) {
        $prop{'decimal'} = $prop{'digit'} = $prop{'numeric'} = "";
    }
    else {
        if ($char =~ /\d/) {
            $prop{'decimal'} = $prop{'digit'} = $prop{'numeric'} = $value;
        }
        else {

            # For non-decimal-digits, we have to read in the Numeric type
            # to distinguish them.  It is not just a matter of integer vs.
            # rational, as some whole number values are not considered digits,
            # e.g., TAMIL NUMBER TEN.
            $prop{'decimal'} = "";

            @NUMERIC_TYPES =_read_table("To/Nt.pl") unless @NUMERIC_TYPES;
            if ((_search(\@NUMERIC_TYPES, 0, $#NUMERIC_TYPES, $code) // "")
                eq 'Digit')
            {
                $prop{'digit'} = $prop{'numeric'} = $value;
            }
            else {
                $prop{'digit'} = "";
                $prop{'numeric'} = $real_to_rational{$value} // $value;
            }
        }
    }

    $prop{'mirrored'} = ($char =~ /\p{Bidi_Mirrored}/) ? 'Y' : 'N';

    %UNICODE_1_NAMES =_read_table("To/Na1.pl", "use_hash") unless %UNICODE_1_NAMES;
    $prop{'unicode10'} = $UNICODE_1_NAMES{$code} // "";

    UnicodeVersion() unless defined $v_unicode_version;
    if ($v_unicode_version ge v6.0.0) {
        $prop{'comment'} = "";
    }
    else {
        %ISO_COMMENT = _read_table("To/Isc.pl", "use_hash") unless %ISO_COMMENT;
        $prop{'comment'} = (defined $ISO_COMMENT{$code})
                           ? $ISO_COMMENT{$code}
                           : "";
    }

    %SIMPLE_UPPER = _read_table("To/Uc.pl", "use_hash") unless %SIMPLE_UPPER;
    $prop{'upper'} = (defined $SIMPLE_UPPER{$code})
                     ? sprintf("%04X", $SIMPLE_UPPER{$code})
                     : "";

    %SIMPLE_LOWER = _read_table("To/Lc.pl", "use_hash") unless %SIMPLE_LOWER;
    $prop{'lower'} = (defined $SIMPLE_LOWER{$code})
                     ? sprintf("%04X", $SIMPLE_LOWER{$code})
                     : "";

    %SIMPLE_TITLE = _read_table("To/Tc.pl", "use_hash") unless %SIMPLE_TITLE;
    $prop{'title'} = (defined $SIMPLE_TITLE{$code})
                     ? sprintf("%04X", $SIMPLE_TITLE{$code})
                     : "";

    $prop{block}  = charblock($code);
    $prop{script} = charscript($code);
    return \%prop;
}

sub _search { # Binary search in a [[lo,hi,prop],[...],...] table.
    my ($table, $lo, $hi, $code) = @_;

    return if $lo > $hi;

    my $mid = int(($lo+$hi) / 2);

    if ($table->[$mid]->[0] < $code) {
	if ($table->[$mid]->[1] >= $code) {
	    return $table->[$mid]->[2];
	} else {
	    _search($table, $mid + 1, $hi, $code);
	}
    } elsif ($table->[$mid]->[0] > $code) {
	_search($table, $lo, $mid - 1, $code);
    } else {
	return $table->[$mid]->[2];
    }
}

sub _read_table ($;$) {

    # Returns the contents of the mktables generated table file located at $1
    # in the form of either an array of arrays or a hash, depending on if the
    # optional second parameter is true (for hash return) or not.  In the case
    # of a hash return, each key is a code point, and its corresponding value
    # is what the table gives as the code point's corresponding value.  In the
    # case of an array return, each outer array denotes a range with [0] the
    # start point of that range; [1] the end point; and [2] the value that
    # every code point in the range has.  The hash return is useful for fast
    # lookup when the table contains only single code point ranges.  The array
    # return takes much less memory when there are large ranges.
    #
    # This function has the side effect of setting
    # $SwashInfo{$property}{'format'} to be the mktables format of the
    #                                       table; and
    # $SwashInfo{$property}{'missing'} to be the value for all entries
    #                                        not listed in the table.
    # where $property is the Unicode property name, preceded by 'To' for map
    # properties., e.g., 'ToSc'.
    #
    # Table entries look like one of:
    # 0000	0040	Common	# [65]
    # 00AA		Latin

    my $table = shift;
    my $return_hash = shift;
    $return_hash = 0 unless defined $return_hash;
    my @return;
    my %return;
    local $_;
    my $list = do "unicore/$table";

    # Look up if this property requires adjustments, which we do below if it
    # does.
    require "unicore/UCD.pl";
    my $property = $table =~ s/\.pl//r;
    $property = $file_to_swash_name{$property};
    my $to_adjust = defined $property
                    && $SwashInfo{$property}{'format'} =~ / ^ a /x;

    for (split /^/m, $list) {
        my ($start, $end, $value) = / ^ (.+?) \t (.*?) \t (.+?)
                                        \s* ( \# .* )?  # Optional comment
                                        $ /x;
        my $decimal_start = hex $start;
        my $decimal_end = ($end eq "") ? $decimal_start : hex $end;
        $value = hex $value if $to_adjust
                               && $SwashInfo{$property}{'format'} eq 'ax';
        if ($return_hash) {
            foreach my $i ($decimal_start .. $decimal_end) {
                $return{$i} = ($to_adjust)
                              ? $value + $i - $decimal_start
                              : $value;
            }
        }
        elsif (! $to_adjust
               && @return
               && $return[-1][1] == $decimal_start - 1
               && $return[-1][2] eq $value)
        {
            # If this is merely extending the previous range, do just that.
            $return[-1]->[1] = $decimal_end;
        }
        else {
            push @return, [ $decimal_start, $decimal_end, $value ];
        }
    }
    return ($return_hash) ? %return : @return;
}

sub charinrange {
    my ($range, $arg) = @_;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::charinrange: unknown code '$arg'"
	unless defined $code;
    _search($range, 0, $#$range, $code);
}


sub charprop ($$;$) {
    my ($input_cp, $prop, $internal_ok) = @_;

    my $cp = _getcode($input_cp);
    croak __PACKAGE__, "::charprop: unknown code point '$input_cp'" unless defined $cp;

    my ($list_ref, $map_ref, $format, $default)
                                      = prop_invmap($prop, $internal_ok);
    return undef unless defined $list_ref;

    my $i = search_invlist($list_ref, $cp);
    croak __PACKAGE__, "::charprop: prop_invmap return is invalid for charprop('$input_cp', '$prop)" unless defined $i;

    # $i is the index into both the inversion list and map of $cp.
    my $map = $map_ref->[$i];

    # Convert enumeration values to their most complete form.
    if (! ref $map) {
        my $long_form = prop_value_aliases($prop, $map);
        $map = $long_form if defined $long_form;
    }

    if ($format =~ / ^ s /x) {  # Scalars
        return join ",", @$map if ref $map; # Convert to scalar with comma
                                            # separated array elements

        # Resolve ambiguity as to whether an all digit value is a code point
        # that should be converted to a character, or whether it is really
        # just a number.  To do this, look at the default.  If it is a
        # non-empty number, we can safely assume the result is also a number.
        if ($map =~ / ^ \d+ $ /ax && $default !~ / ^ \d+ $ /ax) {
            $map = chr $map;
        }
        elsif ($map =~ / ^ (?: Y | N ) $ /x) {

            # prop_invmap() returns these values for properties that are Perl
            # extensions.  But this is misleading.  For now, return undef for
            # these, as currently documented.
            undef $map unless
                exists $prop_aliases{loose_name(lc $prop)};
        }
        return $map;
    }
    elsif ($format eq 'ar') {   # numbers, including rationals
        my $offset = $cp - $list_ref->[$i];
        return $map if $map =~ /nan/i;
        return $map + $offset if $offset != 0;  # If needs adjustment
        return eval $map;   # Convert e.g., 1/2 to 0.5
    }
    elsif ($format =~ /^a/) {   # Some entries need adjusting

        # Linearize sequences into a string.
        return join "", map { chr $_ } @$map if ref $map; # XXX && $format =~ /^ a [dl] /x;

        return "" if $map eq "" && $format =~ /^a.*e/;

        # These are all character mappings.  Return the chr if no adjustment
        # is needed
        return chr $cp if $map eq "0";

        # Convert special entry.
        if ($map eq '<hangul syllable>' && $format eq 'ad') {
            use Unicode::Normalize qw(NFD);
            return NFD(chr $cp);
        }

        # The rest need adjustment from the first entry in the inversion list
        # corresponding to this map.
        my $offset = $cp - $list_ref->[$i];
        return chr($map + $cp - $list_ref->[$i]);
    }
    elsif ($format eq 'n') {    # The name property

        # There are two special cases, handled here.
        if ($map =~ / ( .+ ) <code\ point> $ /x) {
            $map = sprintf("$1%04X", $cp);
        }
        elsif ($map eq '<hangul syllable>') {
            $map = charnames::viacode($cp);
        }
        return $map;
    }
    else {
        croak __PACKAGE__, "::charprop: Internal error: unknown format '$format'.  Please perlbug this";
    }
}


sub charprops_all($) {
    my $input_cp = shift;

    my $cp = _getcode($input_cp);
    croak __PACKAGE__, "::charprops_all: unknown code point '$input_cp'" unless defined $cp;

    my %return;

    require "unicore/UCD.pl";

    foreach my $prop (keys %prop_aliases) {

        # Don't return a Perl extension.  (This is the only one that
        # %prop_aliases has in it.)
        next if $prop eq 'perldecimaldigit';

        # Use long name for $prop in the hash
        $return{scalar prop_aliases($prop)} = charprop($cp, $prop);
    }

    return \%return;
}


my @BLOCKS;
my %BLOCKS;

sub _charblocks {

    # Can't read from the mktables table because it loses the hyphens in the
    # original.
    unless (@BLOCKS) {
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version lt v2.0.0) {
            my $subrange = [ 0, 0x10FFFF, 'No_Block' ];
            push @BLOCKS, $subrange;
            push @{$BLOCKS{'No_Block'}}, $subrange;
        }
        else {
            my $blocksfh = openunicode("Blocks.txt");
	    local $_;
	    local $/ = "\n";
	    while (<$blocksfh>) {

                # Old versions used a different syntax to mark the range.
                $_ =~ s/;\s+/../ if $v_unicode_version lt v3.1.0;

		if (/^([0-9A-F]+)\.\.([0-9A-F]+);\s+(.+)/) {
		    my ($lo, $hi) = (hex($1), hex($2));
		    my $subrange = [ $lo, $hi, $3 ];
		    push @BLOCKS, $subrange;
		    push @{$BLOCKS{$3}}, $subrange;
		}
	    }
            if (! IS_ASCII_PLATFORM) {
                # The first two blocks, through 0xFF, are wrong on EBCDIC
                # platforms.

                my @new_blocks = _read_table("To/Blk.pl");

                # Get rid of the first two ranges in the Unicode version, and
                # replace them with the ones computed by mktables.
                shift @BLOCKS;
                shift @BLOCKS;
                delete $BLOCKS{'Basic Latin'};
                delete $BLOCKS{'Latin-1 Supplement'};

                # But there are multiple entries in the computed versions, and
                # we change their names to (which we know) to be the old-style
                # ones.
                for my $i (0.. @new_blocks - 1) {
                    if ($new_blocks[$i][2] =~ s/Basic_Latin/Basic Latin/
                        or $new_blocks[$i][2] =~
                                    s/Latin_1_Supplement/Latin-1 Supplement/)
                    {
                        push @{$BLOCKS{$new_blocks[$i][2]}}, $new_blocks[$i];
                    }
                    else {
                        splice @new_blocks, $i;
                        last;
                    }
                }
                unshift @BLOCKS, @new_blocks;
            }
	}
    }
}

sub charblock {
    my $arg = shift;

    _charblocks() unless @BLOCKS;

    my $code = _getcode($arg);

    if (defined $code) {
	my $result = _search(\@BLOCKS, 0, $#BLOCKS, $code);
        return $result if defined $result;
        return 'No_Block';
    }
    elsif (exists $BLOCKS{$arg}) {
        return _dclone $BLOCKS{$arg};
    }

    carp __PACKAGE__, "::charblock: unknown code '$arg'";
    return;
}


my @SCRIPTS;
my %SCRIPTS;

sub _charscripts {
    unless (@SCRIPTS) {
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version lt v3.1.0) {
            push @SCRIPTS, [ 0, 0x10FFFF, 'Unknown' ];
        }
        else {
            @SCRIPTS =_read_table("To/Sc.pl");
        }
    }
    foreach my $entry (@SCRIPTS) {
        $entry->[2] =~ s/(_\w)/\L$1/g;  # Preserve old-style casing
        push @{$SCRIPTS{$entry->[2]}}, $entry;
    }
}

sub charscript {
    my $arg = shift;

    _charscripts() unless @SCRIPTS;

    my $code = _getcode($arg);

    if (defined $code) {
	my $result = _search(\@SCRIPTS, 0, $#SCRIPTS, $code);
        return $result if defined $result;
        return $SwashInfo{'ToSc'}{'missing'};
    } elsif (exists $SCRIPTS{$arg}) {
        return _dclone $SCRIPTS{$arg};
    }

    carp __PACKAGE__, "::charscript: unknown code '$arg'";
    return;
}


sub charblocks {
    _charblocks() unless %BLOCKS;
    return _dclone \%BLOCKS;
}


sub charscripts {
    _charscripts() unless %SCRIPTS;
    return _dclone \%SCRIPTS;
}


my %GENERAL_CATEGORIES =
 (
    'L'  =>         'Letter',
    'LC' =>         'CasedLetter',
    'Lu' =>         'UppercaseLetter',
    'Ll' =>         'LowercaseLetter',
    'Lt' =>         'TitlecaseLetter',
    'Lm' =>         'ModifierLetter',
    'Lo' =>         'OtherLetter',
    'M'  =>         'Mark',
    'Mn' =>         'NonspacingMark',
    'Mc' =>         'SpacingMark',
    'Me' =>         'EnclosingMark',
    'N'  =>         'Number',
    'Nd' =>         'DecimalNumber',
    'Nl' =>         'LetterNumber',
    'No' =>         'OtherNumber',
    'P'  =>         'Punctuation',
    'Pc' =>         'ConnectorPunctuation',
    'Pd' =>         'DashPunctuation',
    'Ps' =>         'OpenPunctuation',
    'Pe' =>         'ClosePunctuation',
    'Pi' =>         'InitialPunctuation',
    'Pf' =>         'FinalPunctuation',
    'Po' =>         'OtherPunctuation',
    'S'  =>         'Symbol',
    'Sm' =>         'MathSymbol',
    'Sc' =>         'CurrencySymbol',
    'Sk' =>         'ModifierSymbol',
    'So' =>         'OtherSymbol',
    'Z'  =>         'Separator',
    'Zs' =>         'SpaceSeparator',
    'Zl' =>         'LineSeparator',
    'Zp' =>         'ParagraphSeparator',
    'C'  =>         'Other',
    'Cc' =>         'Control',
    'Cf' =>         'Format',
    'Cs' =>         'Surrogate',
    'Co' =>         'PrivateUse',
    'Cn' =>         'Unassigned',
 );

sub general_categories {
    return _dclone \%GENERAL_CATEGORIES;
}


my %BIDI_TYPES =
 (
   'L'   => 'Left-to-Right',
   'LRE' => 'Left-to-Right Embedding',
   'LRO' => 'Left-to-Right Override',
   'R'   => 'Right-to-Left',
   'AL'  => 'Right-to-Left Arabic',
   'RLE' => 'Right-to-Left Embedding',
   'RLO' => 'Right-to-Left Override',
   'PDF' => 'Pop Directional Format',
   'EN'  => 'European Number',
   'ES'  => 'European Number Separator',
   'ET'  => 'European Number Terminator',
   'AN'  => 'Arabic Number',
   'CS'  => 'Common Number Separator',
   'NSM' => 'Non-Spacing Mark',
   'BN'  => 'Boundary Neutral',
   'B'   => 'Paragraph Separator',
   'S'   => 'Segment Separator',
   'WS'  => 'Whitespace',
   'ON'  => 'Other Neutrals',
 );


sub bidi_types {
    return _dclone \%BIDI_TYPES;
}


my $Composition_Exclusion_re = eval 'qr/\p{Composition_Exclusion}/';

sub compexcl {
    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::compexcl: unknown code '$arg'"
	unless defined $code;

    UnicodeVersion() unless defined $v_unicode_version;
    return if $v_unicode_version lt v3.0.0;

    no warnings "non_unicode";     # So works on non-Unicode code points
    return chr($code) =~ $Composition_Exclusion_re
}


my %CASEFOLD;

sub _casefold {
    unless (%CASEFOLD) {   # Populate the hash
        my ($full_invlist_ref, $full_invmap_ref, undef, $default)
                                                = prop_invmap('Case_Folding');

        # Use the recipe given in the prop_invmap() pod to convert the
        # inversion map into the hash.
        for my $i (0 .. @$full_invlist_ref - 1 - 1) {
            next if $full_invmap_ref->[$i] == $default;
            my $adjust = -1;
            for my $j ($full_invlist_ref->[$i] .. $full_invlist_ref->[$i+1] -1) {
                $adjust++;
                if (! ref $full_invmap_ref->[$i]) {

                    # This is a single character mapping
                    $CASEFOLD{$j}{'status'} = 'C';
                    $CASEFOLD{$j}{'simple'}
                        = $CASEFOLD{$j}{'full'}
                        = $CASEFOLD{$j}{'mapping'}
                        = sprintf("%04X", $full_invmap_ref->[$i] + $adjust);
                    $CASEFOLD{$j}{'code'} = sprintf("%04X", $j);
                    $CASEFOLD{$j}{'turkic'} = "";
                }
                else {  # prop_invmap ensures that $adjust is 0 for a ref
                    $CASEFOLD{$j}{'status'} = 'F';
                    $CASEFOLD{$j}{'full'}
                    = $CASEFOLD{$j}{'mapping'}
                    = join " ", map { sprintf "%04X", $_ }
                                                    @{$full_invmap_ref->[$i]};
                    $CASEFOLD{$j}{'simple'} = "";
                    $CASEFOLD{$j}{'code'} = sprintf("%04X", $j);
                    $CASEFOLD{$j}{'turkic'} = "";
                }
            }
        }

        # We have filled in the full mappings above, assuming there were no
        # simple ones for the ones with multi-character maps.  Now, we find
        # and fix the cases where that assumption was false.
        (my ($simple_invlist_ref, $simple_invmap_ref, undef), $default)
                                        = prop_invmap('Simple_Case_Folding');
        for my $i (0 .. @$simple_invlist_ref - 1 - 1) {
            next if $simple_invmap_ref->[$i] == $default;
            my $adjust = -1;
            for my $j ($simple_invlist_ref->[$i]
                       .. $simple_invlist_ref->[$i+1] -1)
            {
                $adjust++;
                next if $CASEFOLD{$j}{'status'} eq 'C';
                $CASEFOLD{$j}{'status'} = 'S';
                $CASEFOLD{$j}{'simple'}
                    = $CASEFOLD{$j}{'mapping'}
                    = sprintf("%04X", $simple_invmap_ref->[$i] + $adjust);
                $CASEFOLD{$j}{'code'} = sprintf("%04X", $j);
                $CASEFOLD{$j}{'turkic'} = "";
            }
        }

        # We hard-code in the turkish rules
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version ge v3.2.0) {

            # These two code points should already have regular entries, so
            # just fill in the turkish fields
            $CASEFOLD{ord('I')}{'turkic'} = '0131';
            $CASEFOLD{0x130}{'turkic'} = sprintf "%04X", ord('i');
        }
        elsif ($v_unicode_version ge v3.1.0) {

            # These two code points don't have entries otherwise.
            $CASEFOLD{0x130}{'code'} = '0130';
            $CASEFOLD{0x131}{'code'} = '0131';
            $CASEFOLD{0x130}{'status'} = $CASEFOLD{0x131}{'status'} = 'I';
            $CASEFOLD{0x130}{'turkic'}
                = $CASEFOLD{0x130}{'mapping'}
                = $CASEFOLD{0x130}{'full'}
                = $CASEFOLD{0x130}{'simple'}
                = $CASEFOLD{0x131}{'turkic'}
                = $CASEFOLD{0x131}{'mapping'}
                = $CASEFOLD{0x131}{'full'}
                = $CASEFOLD{0x131}{'simple'}
                = sprintf "%04X", ord('i');
        }
    }
}

sub casefold {
    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::casefold: unknown code '$arg'"
	unless defined $code;

    _casefold() unless %CASEFOLD;

    return $CASEFOLD{$code};
}


sub all_casefolds () {
    _casefold() unless %CASEFOLD;
    return _dclone \%CASEFOLD;
}


my %CASESPEC;

sub _casespec {
    unless (%CASESPEC) {
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version ge v2.1.8) {
            my $casespecfh = openunicode("SpecialCasing.txt");
	    local $_;
	    local $/ = "\n";
	    while (<$casespecfh>) {
		if (/^([0-9A-F]+); ([0-9A-F]+(?: [0-9A-F]+)*)?; ([0-9A-F]+(?: [0-9A-F]+)*)?; ([0-9A-F]+(?: [0-9A-F]+)*)?; (\w+(?: \w+)*)?/) {

		    my ($hexcode, $lower, $title, $upper, $condition) =
			($1, $2, $3, $4, $5);
                    if (! IS_ASCII_PLATFORM) { # Remap entry to native
                        foreach my $var_ref (\$hexcode,
                                             \$lower,
                                             \$title,
                                             \$upper)
                        {
                            next unless defined $$var_ref;
                            $$var_ref = join " ",
                                        map { sprintf("%04X",
                                              utf8::unicode_to_native(hex $_)) }
                                        split " ", $$var_ref;
                        }
                    }

		    my $code = hex($hexcode);

                    # In 2.1.8, there were duplicate entries; ignore all but
                    # the first one -- there were no conditions in the file
                    # anyway.
		    if (exists $CASESPEC{$code} && $v_unicode_version ne v2.1.8)
                    {
			if (exists $CASESPEC{$code}->{code}) {
			    my ($oldlower,
				$oldtitle,
				$oldupper,
				$oldcondition) =
				    @{$CASESPEC{$code}}{qw(lower
							   title
							   upper
							   condition)};
			    if (defined $oldcondition) {
				my ($oldlocale) =
				($oldcondition =~ /^([a-z][a-z](?:_\S+)?)/);
				delete $CASESPEC{$code};
				$CASESPEC{$code}->{$oldlocale} =
				{ code      => $hexcode,
				  lower     => $oldlower,
				  title     => $oldtitle,
				  upper     => $oldupper,
				  condition => $oldcondition };
			    }
			}
			my ($locale) =
			    ($condition =~ /^([a-z][a-z](?:_\S+)?)/);
			$CASESPEC{$code}->{$locale} =
			{ code      => $hexcode,
			  lower     => $lower,
			  title     => $title,
			  upper     => $upper,
			  condition => $condition };
		    } else {
			$CASESPEC{$code} =
			{ code      => $hexcode,
			  lower     => $lower,
			  title     => $title,
			  upper     => $upper,
			  condition => $condition };
		    }
		}
	    }
	}
    }
}

sub casespec {
    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::casespec: unknown code '$arg'"
	unless defined $code;

    _casespec() unless %CASESPEC;

    return ref $CASESPEC{$code} ? _dclone $CASESPEC{$code} : $CASESPEC{$code};
}


my %NAMEDSEQ;

sub _namedseq {
    unless (%NAMEDSEQ) {
        my @list = split "\n", do "unicore/Name.pl";
        for (my $i = 0; $i < @list; $i += 3) {
            # Each entry is currently three lines.  The first contains the code
            # points in the sequence separated by spaces.  If this entry
            # doesn't have spaces, it isn't a named sequence.
            next unless $list[$i] =~ /^ [0-9A-F]{4,5} (?: \  [0-9A-F]{4,5} )+ $ /x;

            my $sequence = $list[$i];
            chomp $sequence;

            # And the second is the name
            my $name = $list[$i+1];
            chomp $name;
            my @s = map { chr(hex($_)) } split(' ', $sequence);
            $NAMEDSEQ{$name} = join("", @s);

            # And the third is empty
        }
    }
}

sub namedseq {

    # Use charnames::string_vianame() which now returns this information,
    # unless the caller wants the hash returned, in which case we read it in,
    # and thereafter use it instead of calling charnames, as it is faster.

    my $wantarray = wantarray();
    if (defined $wantarray) {
	if ($wantarray) {
	    if (@_ == 0) {
                _namedseq() unless %NAMEDSEQ;
		return %NAMEDSEQ;
	    } elsif (@_ == 1) {
		my $s;
                if (%NAMEDSEQ) {
                    $s = $NAMEDSEQ{ $_[0] };
                }
                else {
                    $s = charnames::string_vianame($_[0]);
                }
		return defined $s ? map { ord($_) } split('', $s) : ();
	    }
	} elsif (@_ == 1) {
            return $NAMEDSEQ{ $_[0] } if %NAMEDSEQ;
            return charnames::string_vianame($_[0]);
	}
    }
    return;
}

my %NUMERIC;

sub _numeric {
    my @numbers = _read_table("To/Nv.pl");
    foreach my $entry (@numbers) {
        my ($start, $end, $value) = @$entry;

        # If value contains a slash, convert to decimal, add a reverse hash
        # used by charinfo.
        if ((my @rational = split /\//, $value) == 2) {
            my $real = $rational[0] / $rational[1];
            $real_to_rational{$real} = $value;
            $value = $real;

            # Should only be single element, but just in case...
            for my $i ($start .. $end) {
                $NUMERIC{$i} = $value;
            }
        }
        else {
            # The values require adjusting, as is in 'a' format
            for my $i ($start .. $end) {
                $NUMERIC{$i} = $value + $i - $start;
            }
        }
    }

    # Decided unsafe to use these that aren't officially part of the Unicode
    # standard.
    #use Math::Trig;
    #my $pi = acos(-1.0);
    #$NUMERIC{0x03C0} = $pi;

    # Euler's constant, not to be confused with Euler's number
    #$NUMERIC{0x2107} = 0.57721566490153286060651209008240243104215933593992;

    # Euler's number
    #$NUMERIC{0x212F} = 2.7182818284590452353602874713526624977572;

    return;
}






sub num ($;$) {
    my ($string, $retlen_ref) = @_;

    use feature 'unicode_strings';

    _numeric unless %NUMERIC;
    $$retlen_ref = 0 if $retlen_ref;    # Assume will fail

    my $length = length $string;
    return if $length == 0;

    my $first_ord = ord(substr($string, 0, 1));
    return if ! exists  $NUMERIC{$first_ord}
           || ! defined $NUMERIC{$first_ord};

    # Here, we know the first character is numeric
    my $value = $NUMERIC{$first_ord};
    $$retlen_ref = 1 if $retlen_ref;    # Assume only this one is numeric

    return $value if $length == 1;

    # Here, the input is longer than a single character.  To be valid, it must
    # be entirely decimal digits, which means it must start with one.
    return if $string =~ / ^ \D /x;

    # To be a valid decimal number, it should be in a block of 10 consecutive
    # characters, whose values are 0, 1, 2, ... 9.  Therefore this digit's
    # value is its offset in that block from the character that means zero.
    my $zero_ord = $first_ord - $value;

    # Unicode 6.0 instituted the rule that only digits in a consecutive
    # block of 10 would be considered decimal digits.  If this is an earlier
    # release, we verify that this first character is a member of such a
    # block.  That is, that the block of characters surrounding this one
    # consists of all \d characters whose numeric values are the expected
    # ones.  If not, then this single character is numeric, but the string as
    # a whole is not considered to be.
    UnicodeVersion() unless defined $v_unicode_version;
    if ($v_unicode_version lt v6.0.0) {
        for my $i (0 .. 9) {
            my $ord = $zero_ord + $i;
            return unless chr($ord) =~ /\d/;
            my $numeric = $NUMERIC{$ord};
            return unless defined $numeric;
            return unless $numeric == $i;
        }
    }

    for my $i (1 .. $length -1) {

        # Here we know either by verifying, or by fact of the first character
        # being a \d in Unicode 6.0 or later, that any character between the
        # character that means 0, and 9 positions above it must be \d, and
        # must have its value correspond to its offset from the zero.  Any
        # characters outside these 10 do not form a legal number for this
        # function.
        my $ord = ord(substr($string, $i, 1));
        my $digit = $ord - $zero_ord;
        if ($digit < 0 || $digit > 9) {
            $$retlen_ref = $i if $retlen_ref;
            return;
        }
        $value = $value * 10 + $digit;
    }

    $$retlen_ref = $length if $retlen_ref;
    return $value;
}



our %string_property_loose_to_name;
our %ambiguous_names;
our %loose_perlprop_to_name;

sub prop_aliases ($) {
    my $prop = $_[0];
    return unless defined $prop;

    require "unicore/UCD.pl";

    # The property name may be loosely or strictly matched; we don't know yet.
    # But both types use lower-case.
    $prop = lc $prop;

    # It is loosely matched if its lower case isn't known to be strict.
    my $list_ref;
    if (! exists $stricter_to_file_of{$prop}) {
        my $loose = loose_name($prop);

        # There is a hash that converts from any loose name to its standard
        # form, mapping all synonyms for a  name to one name that can be used
        # as a key into another hash.  The whole concept is for memory
        # savings, as the second hash doesn't have to have all the
        # combinations.  Actually, there are two hashes that do the
        # conversion.  One is stored in UCD.pl) for looking up properties
        # matchable in regexes.  This function needs to access string
        # properties, which aren't available in regexes, so a second
        # conversion hash is made for them (stored in UCD.pl).  Look in the
        # string one now, as the rest can have an optional 'is' prefix, which
        # these don't.
        if (exists $string_property_loose_to_name{$loose}) {

            # Convert to its standard loose name.
            $prop = $string_property_loose_to_name{$loose};
        }
        else {
            my $retrying = 0;   # bool.  ? Has an initial 'is' been stripped
        RETRY:
            if (exists $loose_property_name_of{$loose}
                && (! $retrying
                    || ! exists $ambiguous_names{$loose}))
            {
                # Found an entry giving the standard form.  We don't get here
                # (in the test above) when we've stripped off an
                # 'is' and the result is an ambiguous name.  That is because
                # these are official Unicode properties (though Perl can have
                # an optional 'is' prefix meaning the official property), and
                # all ambiguous cases involve a Perl single-form extension
                # for the gc, script, or block properties, and the stripped
                # 'is' means that they mean one of those, and not one of
                # these
                $prop = $loose_property_name_of{$loose};
            }
            elsif (exists $loose_perlprop_to_name{$loose}) {

                # This hash is specifically for this function to list Perl
                # extensions that aren't in the earlier hashes.  If there is
                # only one element, the short and long names are identical.
                # Otherwise the form is already in the same form as
                # %prop_aliases, which is handled at the end of the function.
                $list_ref = $loose_perlprop_to_name{$loose};
                if (@$list_ref == 1) {
                    my @list = ($list_ref->[0], $list_ref->[0]);
                    $list_ref = \@list;
                }
            }
            elsif (! exists $loose_to_file_of{$loose}) {

                # loose_to_file_of is a complete list of loose names.  If not
                # there, the input is unknown.
                return;
            }
            elsif ($loose =~ / [:=] /x) {

                # Here we found the name but not its aliases, so it has to
                # exist.  Exclude property-value combinations.  (This shows up
                # for something like ccc=vr which matches loosely, but is a
                # synonym for ccc=9 which matches only strictly.
                return;
            }
            else {

                # Here it has to exist, and isn't a property-value
                # combination.  This means it must be one of the Perl
                # single-form extensions.  First see if it is for a
                # property-value combination in one of the following
                # properties.
                my @list;
                foreach my $property ("gc", "script") {
                    @list = prop_value_aliases($property, $loose);
                    last if @list;
                }
                if (@list) {

                    # Here, it is one of those property-value combination
                    # single-form synonyms.  There are ambiguities with some
                    # of these.  Check against the list for these, and adjust
                    # if necessary.
                    for my $i (0 .. @list -1) {
                        if (exists $ambiguous_names
                                   {loose_name(lc $list[$i])})
                        {
                            # The ambiguity is resolved by toggling whether or
                            # not it has an 'is' prefix
                            $list[$i] =~ s/^Is_// or $list[$i] =~ s/^/Is_/;
                        }
                    }
                    return @list;
                }

                # Here, it wasn't one of the gc or script single-form
                # extensions.  It could be a block property single-form
                # extension.  An 'in' prefix definitely means that, and should
                # be looked up without the prefix.  However, starting in
                # Unicode 6.1, we have to special case 'indic...', as there
                # is a property that begins with that name.   We shouldn't
                # strip the 'in' from that.   I'm (khw) generalizing this to
                # 'indic' instead of the single property, because I suspect
                # that others of this class may come along in the future.
                # However, this could backfire and a block created whose name
                # begins with 'dic...', and we would want to strip the 'in'.
                # At which point this would have to be tweaked.
                my $began_with_in = $loose =~ s/^in(?!dic)//;
                @list = prop_value_aliases("block", $loose);
                if (@list) {
                    map { $_ =~ s/^/In_/ } @list;
                    return @list;
                }

                # Here still haven't found it.  The last opportunity for it
                # being valid is only if it began with 'is'.  We retry without
                # the 'is', setting a flag to that effect so that we don't
                # accept things that begin with 'isis...'
                if (! $retrying && ! $began_with_in && $loose =~ s/^is//) {
                    $retrying = 1;
                    goto RETRY;
                }

                # Here, didn't find it.  Since it was in %loose_to_file_of, we
                # should have been able to find it.
                carp __PACKAGE__, "::prop_aliases: Unexpectedly could not find '$prop'.  Send bug report to perlbug\@perl.org";
                return;
            }
        }
    }

    if (! $list_ref) {
        # Here, we have set $prop to a standard form name of the input.  Look
        # it up in the structure created by mktables for this purpose, which
        # contains both strict and loosely matched properties.  Avoid
        # autovivifying.
        $list_ref = $prop_aliases{$prop} if exists $prop_aliases{$prop};
        return unless $list_ref;
    }

    # The full name is in element 1.
    return $list_ref->[1] unless wantarray;

    return @{_dclone $list_ref};
}


our %loose_to_standard_value;
our %prop_value_aliases;

sub prop_values ($) {
    my $prop = shift;
    return undef unless defined $prop;

    require "unicore/UCD.pl";

    # Find the property name synonym that's used as the key in other hashes,
    # which is element 0 in the returned list.
    ($prop) = prop_aliases($prop);
    return undef if ! $prop;
    $prop = loose_name(lc $prop);

    # Here is a legal property.
    return undef unless exists $prop_value_aliases{$prop};
    my @return;
    foreach my $value_key (sort { lc $a cmp lc $b }
                            keys %{$prop_value_aliases{$prop}})
    {
        push @return, $prop_value_aliases{$prop}{$value_key}[0];
    }
    return @return;
}


sub prop_value_aliases ($$) {
    my ($prop, $value) = @_;
    return unless defined $prop && defined $value;

    require "unicore/UCD.pl";

    # Find the property name synonym that's used as the key in other hashes,
    # which is element 0 in the returned list.
    ($prop) = prop_aliases($prop);
    return if ! $prop;
    $prop = loose_name(lc $prop);

    # Here is a legal property, but the hash below (created by mktables for
    # this purpose) only knows about the properties that have a very finite
    # number of potential values, that is not ones whose value could be
    # anything, like most (if not all) string properties.  These don't have
    # synonyms anyway.  Simply return the input.  For example, there is no
    # synonym for ('Uppercase_Mapping', A').
    if (! exists $prop_value_aliases{$prop}) {

        # Here, we have a legal property, but an unknown value.  Since the
        # property is legal, if it isn't in the prop_aliases hash, it must be
        # a Perl-extension All perl extensions are binary, hence are
        # enumerateds, which means that we know that the input unknown value
        # is illegal.
        return if ! exists $prop_aliases{$prop};

        # Otherwise, we assume it's valid, as documented.
        return $value;
    }

    # The value name may be loosely or strictly matched; we don't know yet.
    # But both types use lower-case.
    $value = lc $value;

    # If the name isn't found under loose matching, it certainly won't be
    # found under strict
    my $loose_value = loose_name($value);
    return unless exists $loose_to_standard_value{"$prop=$loose_value"};

    # Similarly if the combination under loose matching doesn't exist, it
    # won't exist under strict.
    my $standard_value = $loose_to_standard_value{"$prop=$loose_value"};
    return unless exists $prop_value_aliases{$prop}{$standard_value};

    # Here we did find a combination under loose matching rules.  But it could
    # be that is a strict property match that shouldn't have matched.
    # %prop_value_aliases is set up so that the strict matches will appear as
    # if they were in loose form.  Thus, if the non-loose version is legal,
    # we're ok, can skip the further check.
    if (! exists $stricter_to_file_of{"$prop=$value"}

        # We're also ok and skip the further check if value loosely matches.
        # mktables has verified that no strict name under loose rules maps to
        # an existing loose name.  This code relies on the very limited
        # circumstances that strict names can be here.  Strict name matching
        # happens under two conditions:
        # 1) when the name begins with an underscore.  But this function
        #    doesn't accept those, and %prop_value_aliases doesn't have
        #    them.
        # 2) When the values are numeric, in which case we need to look
        #    further, but their squeezed-out loose values will be in
        #    %stricter_to_file_of
        && exists $stricter_to_file_of{"$prop=$loose_value"})
    {
        # The only thing that's legal loosely under strict is that can have an
        # underscore between digit pairs XXX
        while ($value =~ s/(\d)_(\d)/$1$2/g) {}
        return unless exists $stricter_to_file_of{"$prop=$value"};
    }

    # Here, we know that the combination exists.  Return it.
    my $list_ref = $prop_value_aliases{$prop}{$standard_value};
    if (@$list_ref > 1) {
        # The full name is in element 1.
        return $list_ref->[1] unless wantarray;

        return @{_dclone $list_ref};
    }

    return $list_ref->[0] unless wantarray;

    # Only 1 element means that it repeats
    return ( $list_ref->[0], $list_ref->[0] );
}

$MAX_CP = (~0) >> 1;



our %loose_defaults;
our $MAX_UNICODE_CODEPOINT;

sub prop_invlist ($;$) {
    my $prop = $_[0];

    # Undocumented way to get at Perl internal properties; it may be changed
    # or removed without notice at any time.
    my $internal_ok = defined $_[1] && $_[1] eq '_perl_core_internal_ok';

    return if ! defined $prop;

    # Warnings for these are only for regexes, so not applicable to us
    no warnings 'deprecated';

    # Get the swash definition of the property-value.
    my $swash = SWASHNEW(__PACKAGE__, $prop, undef, 1, 0);

    # Fail if not found, or isn't a boolean property-value, or is a
    # user-defined property, or is internal-only.
    return if ! $swash
              || ref $swash eq ""
              || $swash->{'BITS'} != 1
              || $swash->{'USER_DEFINED'}
              || (! $internal_ok && $prop =~ /^\s*_/);

    if ($swash->{'EXTRAS'}) {
        carp __PACKAGE__, "::prop_invlist: swash returned for $prop unexpectedly has EXTRAS magic";
        return;
    }
    if ($swash->{'SPECIALS'}) {
        carp __PACKAGE__, "::prop_invlist: swash returned for $prop unexpectedly has SPECIALS magic";
        return;
    }

    my @invlist;

    if ($swash->{'LIST'} =~ /^V/) {

        # A 'V' as the first character marks the input as already an inversion
        # list, in which case, all we need to do is put the remaining lines
        # into our array.
        @invlist = split "\n", $swash->{'LIST'} =~ s/ \s* (?: \# .* )? $ //xmgr;
        shift @invlist;
    }
    else {
        # The input lines look like:
        # 0041\t005A   # [26]
        # 005F

        # Split into lines, stripped of trailing comments
        foreach my $range (split "\n",
                              $swash->{'LIST'} =~ s/ \s* (?: \# .* )? $ //xmgr)
        {
            # And find the beginning and end of the range on the line
            my ($hex_begin, $hex_end) = split "\t", $range;
            my $begin = hex $hex_begin;

            # If the new range merely extends the old, we remove the marker
            # created the last time through the loop for the old's end, which
            # causes the new one's end to be used instead.
            if (@invlist && $begin == $invlist[-1]) {
                pop @invlist;
            }
            else {
                # Add the beginning of the range
                push @invlist, $begin;
            }

            if (defined $hex_end) { # The next item starts with the code point 1
                                    # beyond the end of the range.
                no warnings 'portable';
                my $end = hex $hex_end;
                last if $end == $MAX_CP;
                push @invlist, $end + 1;
            }
            else {  # No end of range, is a single code point.
                push @invlist, $begin + 1;
            }
        }
    }

    # Could need to be inverted: add or subtract a 0 at the beginning of the
    # list.
    if ($swash->{'INVERT_IT'}) {
        if (@invlist && $invlist[0] == 0) {
            shift @invlist;
        }
        else {
            unshift @invlist, 0;
        }
    }

    return @invlist;
}




our @algorithmic_named_code_points;
our $HANGUL_BEGIN;
our $HANGUL_COUNT;

sub prop_invmap ($;$) {

    croak __PACKAGE__, "::prop_invmap: must be called in list context" unless wantarray;

    my $prop = $_[0];
    return unless defined $prop;

    # Undocumented way to get at Perl internal properties; it may be changed
    # or removed without notice at any time.  It currently also changes the
    # output to use the format specified in the file rather than the one we
    # normally compute and return
    my $internal_ok = defined $_[1] && $_[1] eq '_perl_core_internal_ok';

    # Fail internal properties
    return if $prop =~ /^_/ && ! $internal_ok;

    # The values returned by this function.
    my (@invlist, @invmap, $format, $missing);

    # The swash has two components we look at, the base list, and a hash,
    # named 'SPECIALS', containing any additional members whose mappings don't
    # fit into the base list scheme of things.  These generally 'override'
    # any value in the base list for the same code point.
    my $overrides;

    require "unicore/UCD.pl";

RETRY:

    # If there are multiple entries for a single code point
    my $has_multiples = 0;

    # Try to get the map swash for the property.  They have 'To' prepended to
    # the property name, and 32 means we will accept 32 bit return values.
    # The 0 means we aren't calling this from tr///.
    my $swash = SWASHNEW(__PACKAGE__, "To$prop", undef, 32, 0);

    # If didn't find it, could be because needs a proxy.  And if was the
    # 'Block' or 'Name' property, use a proxy even if did find it.  Finding it
    # in these cases would be the result of the installation changing mktables
    # to output the Block or Name tables.  The Block table gives block names
    # in the new-style, and this routine is supposed to return old-style block
    # names.  The Name table is valid, but we need to execute the special code
    # below to add in the algorithmic-defined name entries.
    # And NFKCCF needs conversion, so handle that here too.
    if (ref $swash eq ""
        || $swash->{'TYPE'} =~ / ^ To (?: Blk | Na | NFKCCF ) $ /x)
    {

        # Get the short name of the input property, in standard form
        my ($second_try) = prop_aliases($prop);
        return unless $second_try;
        $second_try = loose_name(lc $second_try);

        if ($second_try eq "in") {

            # This property is identical to age for inversion map purposes
            $prop = "age";
            goto RETRY;
        }
        elsif ($second_try =~ / ^ s ( cf | fc | [ltu] c ) $ /x) {

            # These properties use just the LIST part of the full mapping,
            # which includes the simple maps that are otherwise overridden by
            # the SPECIALS.  So all we need do is to not look at the SPECIALS;
            # set $overrides to indicate that
            $overrides = -1;

            # The full name is the simple name stripped of its initial 's'
            $prop = $1;

            # .. except for this case
            $prop = 'cf' if $prop eq 'fc';

            goto RETRY;
        }
        elsif ($second_try eq "blk") {

            # We use the old block names.  Just create a fake swash from its
            # data.
            _charblocks();
            my %blocks;
            $blocks{'LIST'} = "";
            $blocks{'TYPE'} = "ToBlk";
            $SwashInfo{ToBlk}{'missing'} = "No_Block";
            $SwashInfo{ToBlk}{'format'} = "s";

            foreach my $block (@BLOCKS) {
                $blocks{'LIST'} .= sprintf "%x\t%x\t%s\n",
                                           $block->[0],
                                           $block->[1],
                                           $block->[2];
            }
            $swash = \%blocks;
        }
        elsif ($second_try eq "na") {

            # Use the combo file that has all the Name-type properties in it,
            # extracting just the ones that are for the actual 'Name'
            # property.  And create a fake swash from it.
            my %names;
            $names{'LIST'} = "";
            my $original = do "unicore/Name.pl";

            # Change the double \n format of the file back to single lines
            # with a tab
            $original =~ s/\n\n/\e/g;   # Use a control that shouldn't occur
                                        #in the file
            $original =~ s/\n/\t/g;
            $original =~ s/\e/\n/g;

            my $algorithm_names = \@algorithmic_named_code_points;

            # We need to remove the names from it that are aliases.  For that
            # we need to also read in that table.  Create a hash with the keys
            # being the code points, and the values being a list of the
            # aliases for the code point key.
            my ($aliases_code_points, $aliases_maps, undef, undef)
                  = &prop_invmap("_Perl_Name_Alias", '_perl_core_internal_ok');
            my %aliases;
            for (my $i = 0; $i < @$aliases_code_points; $i++) {
                my $code_point = $aliases_code_points->[$i];
                $aliases{$code_point} = $aliases_maps->[$i];

                # If not already a list, make it into one, so that later we
                # can treat things uniformly
                if (! ref $aliases{$code_point}) {
                    $aliases{$code_point} = [ $aliases{$code_point} ];
                }

                # Remove the alias type from the entry, retaining just the
                # name.
                map { s/:.*// } @{$aliases{$code_point}};
            }

            my $i = 0;
            foreach my $line (split "\n", $original) {
                my ($hex_code_point, $name) = split "\t", $line;

                # Weeds out any comments, blank lines, and named sequences
                next if $hex_code_point =~ /[^[:xdigit:]]/a;

                my $code_point = hex $hex_code_point;

                # The name of all controls is the default: the empty string.
                # The set of controls is immutable
                next if chr($code_point) =~ /[[:cntrl:]]/u;

                # If this is a name_alias, it isn't a name
                next if grep { $_ eq $name } @{$aliases{$code_point}};

                # If we are beyond where one of the special lines needs to
                # be inserted ...
                while ($i < @$algorithm_names
                    && $code_point > $algorithm_names->[$i]->{'low'})
                {

                    # ... then insert it, ahead of what we were about to
                    # output
                    $names{'LIST'} .= sprintf "%x\t%x\t%s\n",
                                            $algorithm_names->[$i]->{'low'},
                                            $algorithm_names->[$i]->{'high'},
                                            $algorithm_names->[$i]->{'name'};

                    # Done with this range.
                    $i++;

                    # We loop until all special lines that precede the next
                    # regular one are output.
                }

                # Here, is a normal name.
                $names{'LIST'} .= sprintf "%x\t\t%s\n", $code_point, $name;
            } # End of loop through all the names

            $names{'TYPE'} = "ToNa";
            $SwashInfo{ToNa}{'missing'} = "";
            $SwashInfo{ToNa}{'format'} = "n";
            $swash = \%names;
        }
        elsif ($second_try =~ / ^ ( d [mt] ) $ /x) {

            # The file is a combination of dt and dm properties.  Create a
            # fake swash from the portion that we want.
            my $original = do "unicore/Decomposition.pl";
            my %decomps;

            if ($second_try eq 'dt') {
                $decomps{'TYPE'} = "ToDt";
                $SwashInfo{'ToDt'}{'missing'} = "None";
                $SwashInfo{'ToDt'}{'format'} = "s";
            }   # 'dm' is handled below, with 'nfkccf'

            $decomps{'LIST'} = "";

            # This property has one special range not in the file: for the
            # hangul syllables.  But not in Unicode version 1.
            UnicodeVersion() unless defined $v_unicode_version;
            my $done_hangul = ($v_unicode_version lt v2.0.0)
                              ? 1
                              : 0;    # Have we done the hangul range ?
            foreach my $line (split "\n", $original) {
                my ($hex_lower, $hex_upper, $type_and_map) = split "\t", $line;
                my $code_point = hex $hex_lower;
                my $value;
                my $redo = 0;

                # The type, enclosed in <...>, precedes the mapping separated
                # by blanks
                if ($type_and_map =~ / ^ < ( .* ) > \s+ (.*) $ /x) {
                    $value = ($second_try eq 'dt') ? $1 : $2
                }
                else {  # If there is no type specified, it's canonical
                    $value = ($second_try eq 'dt')
                             ? "Canonical" :
                             $type_and_map;
                }

                # Insert the hangul range at the appropriate spot.
                if (! $done_hangul && $code_point > $HANGUL_BEGIN) {
                    $done_hangul = 1;
                    $decomps{'LIST'} .=
                                sprintf "%x\t%x\t%s\n",
                                        $HANGUL_BEGIN,
                                        $HANGUL_BEGIN + $HANGUL_COUNT - 1,
                                        ($second_try eq 'dt')
                                        ? "Canonical"
                                        : "<hangul syllable>";
                }

                if ($value =~ / / && $hex_upper ne "" && $hex_upper ne $hex_lower) {
                    $line = sprintf("%04X\t%s\t%s", hex($hex_lower) + 1, $hex_upper, $value);
                    $hex_upper = "";
                    $redo = 1;
                }

                # And append this to our constructed LIST.
                $decomps{'LIST'} .= "$hex_lower\t$hex_upper\t$value\n";

                redo if $redo;
            }
            $swash = \%decomps;
        }
        elsif ($second_try ne 'nfkccf') { # Don't know this property. Fail.
            return;
        }

        if ($second_try eq 'nfkccf' || $second_try eq 'dm') {

            # The 'nfkccf' property is stored in the old format for backwards
            # compatibility for any applications that has read its file
            # directly before prop_invmap() existed.
            # And the code above has extracted the 'dm' property from its file
            # yielding the same format.  So here we convert them to adjusted
            # format for compatibility with the other properties similar to
            # them.
            my %revised_swash;

            # We construct a new converted list.
            my $list = "";

            my @ranges = split "\n", $swash->{'LIST'};
            for (my $i = 0; $i < @ranges; $i++) {
                my ($hex_begin, $hex_end, $map) = split "\t", $ranges[$i];

                # The dm property has maps that are space separated sequences
                # of code points, as well as the special entry "<hangul
                # syllable>, which also contains a blank.
                my @map = split " ", $map;
                if (@map > 1) {

                    # If it's just the special entry, append as-is.
                    if ($map eq '<hangul syllable>') {
                        $list .= "$ranges[$i]\n";
                    }
                    else {

                        # These should all be single-element ranges.
                        croak __PACKAGE__, "::prop_invmap: Not expecting a mapping with multiple code points in a multi-element range, $ranges[$i]" if $hex_end ne "" && $hex_end ne $hex_begin;

                        # Convert them to decimal, as that's what's expected.
                        $list .= "$hex_begin\t\t"
                            . join(" ", map { hex } @map)
                            . "\n";
                    }
                    next;
                }

                # Here, the mapping doesn't have a blank, is for a single code
                # point.
                my $begin = hex $hex_begin;
                my $end = (defined $hex_end && $hex_end ne "")
                        ? hex $hex_end
                        : $begin;

                # Again, the output is to be in decimal.
                my $decimal_map = hex $map;

                # We know that multi-element ranges with the same mapping
                # should not be adjusted, as after the adjustment
                # multi-element ranges are for consecutive increasing code
                # points.  Further, the final element in the list won't be
                # adjusted, as there is nothing after it to include in the
                # adjustment
                if ($begin != $end || $i == @ranges -1) {

                    # So just convert these to single-element ranges
                    foreach my $code_point ($begin .. $end) {
                        $list .= sprintf("%04X\t\t%d\n",
                                        $code_point, $decimal_map);
                    }
                }
                else {

                    # Here, we have a candidate for adjusting.  What we do is
                    # look through the subsequent adjacent elements in the
                    # input.  If the map to the next one differs by 1 from the
                    # one before, then we combine into a larger range with the
                    # initial map.  Loop doing this until we find one that
                    # can't be combined.

                    my $offset = 0;     # How far away are we from the initial
                                        # map
                    my $squished = 0;   # ? Did we squish at least two
                                        # elements together into one range
                    for ( ; $i < @ranges; $i++) {
                        my ($next_hex_begin, $next_hex_end, $next_map)
                                                = split "\t", $ranges[$i+1];

                        # In the case of 'dm', the map may be a sequence of
                        # multiple code points, which are never combined with
                        # another range
                        last if $next_map =~ / /;

                        $offset++;
                        my $next_decimal_map = hex $next_map;

                        # If the next map is not next in sequence, it
                        # shouldn't be combined.
                        last if $next_decimal_map != $decimal_map + $offset;

                        my $next_begin = hex $next_hex_begin;

                        # Likewise, if the next element isn't adjacent to the
                        # previous one, it shouldn't be combined.
                        last if $next_begin != $begin + $offset;

                        my $next_end = (defined $next_hex_end
                                        && $next_hex_end ne "")
                                            ? hex $next_hex_end
                                            : $next_begin;

                        # And finally, if the next element is a multi-element
                        # range, it shouldn't be combined.
                        last if $next_end != $next_begin;

                        # Here, we will combine.  Loop to see if we should
                        # combine the next element too.
                        $squished = 1;
                    }

                    if ($squished) {

                        # Here, 'i' is the element number of the last element to
                        # be combined, and the range is single-element, or we
                        # wouldn't be combining.  Get it's code point.
                        my ($hex_end, undef, undef) = split "\t", $ranges[$i];
                        $list .= "$hex_begin\t$hex_end\t$decimal_map\n";
                    } else {

                        # Here, no combining done.  Just append the initial
                        # (and current) values.
                        $list .= "$hex_begin\t\t$decimal_map\n";
                    }
                }
            } # End of loop constructing the converted list

            # Finish up the data structure for our converted swash
            my $type = ($second_try eq 'nfkccf') ? 'ToNFKCCF' : 'ToDm';
            $revised_swash{'LIST'} = $list;
            $revised_swash{'TYPE'} = $type;
            $revised_swash{'SPECIALS'} = $swash->{'SPECIALS'};
            $swash = \%revised_swash;

            $SwashInfo{$type}{'missing'} = 0;
            $SwashInfo{$type}{'format'} = 'a';
        }
    }

    if ($swash->{'EXTRAS'}) {
        carp __PACKAGE__, "::prop_invmap: swash returned for $prop unexpectedly has EXTRAS magic";
        return;
    }

    # Here, have a valid swash return.  Examine it.
    my $returned_prop = $swash->{'TYPE'};

    # All properties but binary ones should have 'missing' and 'format'
    # entries
    $missing = $SwashInfo{$returned_prop}{'missing'};
    $missing = 'N' unless defined $missing;

    $format = $SwashInfo{$returned_prop}{'format'};
    $format = 'b' unless defined $format;

    my $requires_adjustment = $format =~ /^a/;

    if ($swash->{'LIST'} =~ /^V/) {
        @invlist = split "\n", $swash->{'LIST'} =~ s/ \s* (?: \# .* )? $ //xmgr;

        shift @invlist;     # Get rid of 'V';

        # Could need to be inverted: add or subtract a 0 at the beginning of
        # the list.
        if ($swash->{'INVERT_IT'}) {
            if (@invlist && $invlist[0] == 0) {
                shift @invlist;
            }
            else {
                unshift @invlist, 0;
            }
        }

        if (@invlist) {
            foreach my $i (0 .. @invlist - 1) {
                $invmap[$i] = ($i % 2 == 0) ? 'Y' : 'N'
            }

            # The map includes lines for all code points; add one for the range
            # from 0 to the first Y.
            if ($invlist[0] != 0) {
                unshift @invlist, 0;
                unshift @invmap, 'N';
            }
        }
    }
    else {
        if ($swash->{'INVERT_IT'}) {
            croak __PACKAGE__, ":prop_invmap: Don't know how to deal with inverted";
        }

        # The LIST input lines look like:
        # ...
        # 0374\t\tCommon
        # 0375\t0377\tGreek   # [3]
        # 037A\t037D\tGreek   # [4]
        # 037E\t\tCommon
        # 0384\t\tGreek
        # ...
        #
        # Convert them to like
        # 0374 => Common
        # 0375 => Greek
        # 0378 => $missing
        # 037A => Greek
        # 037E => Common
        # 037F => $missing
        # 0384 => Greek
        #
        # For binary properties, the final non-comment column is absent, and
        # assumed to be 'Y'.

        foreach my $range (split "\n", $swash->{'LIST'}) {
            $range =~ s/ \s* (?: \# .* )? $ //xg; # rmv trailing space, comments

            # Find the beginning and end of the range on the line
            my ($hex_begin, $hex_end, $map) = split "\t", $range;
            my $begin = hex $hex_begin;
            no warnings 'portable';
            my $end = (defined $hex_end && $hex_end ne "")
                    ? hex $hex_end
                    : $begin;

            # Each time through the loop (after the first):
            # $invlist[-2] contains the beginning of the previous range processed
            # $invlist[-1] contains the end+1 of the previous range processed
            # $invmap[-2] contains the value of the previous range processed
            # $invmap[-1] contains the default value for missing ranges
            #                                                       ($missing)
            #
            # Thus, things are set up for the typical case of a new
            # non-adjacent range of non-missings to be added.  But, if the new
            # range is adjacent, it needs to replace the [-1] element; and if
            # the new range is a multiple value of the previous one, it needs
            # to be added to the [-2] map element.

            # The first time through, everything will be empty.  If the
            # property doesn't have a range that begins at 0, add one that
            # maps to $missing
            if (! @invlist) {
                if ($begin != 0) {
                    push @invlist, 0;
                    push @invmap, $missing;
                }
            }
            elsif (@invlist > 1 && $invlist[-2] == $begin) {

                # Here we handle the case where the input has multiple entries
                # for each code point.  mktables should have made sure that
                # each such range contains only one code point.  At this
                # point, $invlist[-1] is the $missing that was added at the
                # end of the last loop iteration, and [-2] is the last real
                # input code point, and that code point is the same as the one
                # we are adding now, making the new one a multiple entry.  Add
                # it to the existing entry, either by pushing it to the
                # existing list of multiple entries, or converting the single
                # current entry into a list with both on it.  This is all we
                # need do for this iteration.

                if ($end != $begin) {
                    croak __PACKAGE__, ":prop_invmap: Multiple maps per code point in '$prop' require single-element ranges: begin=$begin, end=$end, map=$map";
                }
                if (! ref $invmap[-2]) {
                    $invmap[-2] = [ $invmap[-2], $map ];
                }
                else {
                    push @{$invmap[-2]}, $map;
                }
                $has_multiples = 1;
                next;
            }
            elsif ($invlist[-1] == $begin) {

                # If the input isn't in the most compact form, so that there
                # are two adjacent ranges that map to the same thing, they
                # should be combined (EXCEPT where the arrays require
                # adjustments, in which case everything is already set up
                # correctly).  This happens in our constructed dt mapping, as
                # Element [-2] is the map for the latest range so far
                # processed.  Just set the beginning point of the map to
                # $missing (in invlist[-1]) to 1 beyond where this range ends.
                # For example, in
                # 12\t13\tXYZ
                # 14\t17\tXYZ
                # we have set it up so that it looks like
                # 12 => XYZ
                # 14 => $missing
                #
                # We now see that it should be
                # 12 => XYZ
                # 18 => $missing
                if (! $requires_adjustment && @invlist > 1 && ( (defined $map)
                                    ? $invmap[-2] eq $map
                                    : $invmap[-2] eq 'Y'))
                {
                    $invlist[-1] = $end + 1;
                    next;
                }

                # Here, the range started in the previous iteration that maps
                # to $missing starts at the same code point as this range.
                # That means there is no gap to fill that that range was
                # intended for, so we just pop it off the parallel arrays.
                pop @invlist;
                pop @invmap;
            }

            # Add the range beginning, and the range's map.
            push @invlist, $begin;
            if ($returned_prop eq 'ToDm') {

                # The decomposition maps are either a line like <hangul
                # syllable> which are to be taken as is; or a sequence of code
                # points in hex and separated by blanks.  Convert them to
                # decimal, and if there is more than one, use an anonymous
                # array as the map.
                if ($map =~ /^ < /x) {
                    push @invmap, $map;
                }
                else {
                    my @map = split " ", $map;
                    if (@map == 1) {
                        push @invmap, $map[0];
                    }
                    else {
                        push @invmap, \@map;
                    }
                }
            }
            else {

                # Otherwise, convert hex formatted list entries to decimal;
                # add a 'Y' map for the missing value in binary properties, or
                # otherwise, use the input map unchanged.
                $map = ($format eq 'x' || $format eq 'ax')
                    ? hex $map
                    : $format eq 'b'
                    ? 'Y'
                    : $map;
                push @invmap, $map;
            }

            # We just started a range.  It ends with $end.  The gap between it
            # and the next element in the list must be filled with a range
            # that maps to the default value.  If there is no gap, the next
            # iteration will pop this, unless there is no next iteration, and
            # we have filled all of the Unicode code space, so check for that
            # and skip.
            if ($end < $MAX_CP) {
                push @invlist, $end + 1;
                push @invmap, $missing;
            }
        }
    }

    # If the property is empty, make all code points use the value for missing
    # ones.
    if (! @invlist) {
        push @invlist, 0;
        push @invmap, $missing;
    }

    # The final element is always for just the above-Unicode code points.  If
    # not already there, add it.  It merely splits the current final range
    # that extends to infinity into two elements, each with the same map.
    # (This is to conform with the API that says the final element is for
    # $MAX_UNICODE_CODEPOINT + 1 .. INFINITY.)
    if ($invlist[-1] != $MAX_UNICODE_CODEPOINT + 1) {
        push @invmap, $invmap[-1];
        push @invlist, $MAX_UNICODE_CODEPOINT + 1;
    }

    # The second component of the map are those values that require
    # non-standard specification, stored in SPECIALS.  These override any
    # duplicate code points in LIST.  If we are using a proxy, we may have
    # already set $overrides based on the proxy.
    $overrides = $swash->{'SPECIALS'} unless defined $overrides;
    if ($overrides) {

        # A negative $overrides implies that the SPECIALS should be ignored,
        # and a simple 'a' list is the value.
        if ($overrides < 0) {
            $format = 'a';
        }
        else {

            # Currently, all overrides are for properties that normally map to
            # single code points, but now some will map to lists of code
            # points (but there is an exception case handled below).
            $format = 'al';

            # Look through the overrides.
            foreach my $cp_maybe_utf8 (keys %$overrides) {
                my $cp;
                my @map;

                # If the overrides came from SPECIALS, the code point keys are
                # packed UTF-8.
                if ($overrides == $swash->{'SPECIALS'}) {
                    $cp = $cp_maybe_utf8;
                    if (! utf8::decode($cp)) {
                        croak __PACKAGE__, "::prop_invmap: Malformed UTF-8: ",
                              map { sprintf("\\x{%02X}", unpack("C", $_)) }
                                                                split "", $cp;
                    }

                    $cp = unpack("W", $cp);
                    @map = unpack "W*", $swash->{'SPECIALS'}{$cp_maybe_utf8};

                    # The empty string will show up unpacked as an empty
                    # array.
                    $format = 'ale' if @map == 0;
                }
                else {

                    # But if we generated the overrides, we didn't bother to
                    # pack them, and we, so far, do this only for properties
                    # that are 'a' ones.
                    $cp = $cp_maybe_utf8;
                    @map = hex $overrides->{$cp};
                    $format = 'a';
                }

                # Find the range that the override applies to.
                my $i = search_invlist(\@invlist, $cp);
                if ($cp < $invlist[$i] || $cp >= $invlist[$i + 1]) {
                    croak __PACKAGE__, "::prop_invmap: wrong_range, cp=$cp; i=$i, current=$invlist[$i]; next=$invlist[$i + 1]"
                }

                # And what that range currently maps to
                my $cur_map = $invmap[$i];

                # If there is a gap between the next range and the code point
                # we are overriding, we have to add elements to both arrays to
                # fill that gap, using the map that applies to it, which is
                # $cur_map, since it is part of the current range.
                if ($invlist[$i + 1] > $cp + 1) {
                    #use feature 'say';
                    #say "Before splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;

                    splice @invlist, $i + 1, 0, $cp + 1;
                    splice @invmap, $i + 1, 0, $cur_map;

                    #say "After splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;
                }

                # If the remaining portion of the range is multiple code
                # points (ending with the one we are replacing, guaranteed by
                # the earlier splice).  We must split it into two
                if ($invlist[$i] < $cp) {
                    $i++;   # Compensate for the new element

                    #use feature 'say';
                    #say "Before splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;

                    splice @invlist, $i, 0, $cp;
                    splice @invmap, $i, 0, 'dummy';

                    #say "After splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;
                }

                # Here, the range we are overriding contains a single code
                # point.  The result could be the empty string, a single
                # value, or a list.  If the last case, we use an anonymous
                # array.
                $invmap[$i] = (scalar @map == 0)
                               ? ""
                               : (scalar @map > 1)
                                  ? \@map
                                  : $map[0];
            }
        }
    }
    elsif ($format eq 'x') {

        # All hex-valued properties are really to code points, and have been
        # converted to decimal.
        $format = 's';
    }
    elsif ($returned_prop eq 'ToDm') {
        $format = 'ad';
    }
    elsif ($format eq 'sw') { # blank-separated elements to form a list.
        map { $_ = [ split " ", $_  ] if $_ =~ / / } @invmap;
        $format = 'sl';
    }
    elsif ($returned_prop =~ / To ( _Perl )? NameAlias/x) {

        # This property currently doesn't have any lists, but theoretically
        # could
        $format = 'sl';
    }
    elsif ($returned_prop eq 'ToPerlDecimalDigit') {
        $format = 'ae';
    }
    elsif ($returned_prop eq 'ToNv') {

        # The one property that has this format is stored as a delta, so needs
        # to indicate that need to add code point to it.
        $format = 'ar';
    }
    elsif ($format eq 'ax') {

        # Normally 'ax' properties have overrides, and will have been handled
        # above, but if not, they still need adjustment, and the hex values
        # have already been converted to decimal
        $format = 'a';
    }
    elsif ($format ne 'n' && $format !~ / ^ a /x) {

        # All others are simple scalars
        $format = 's';
    }
    if ($has_multiples &&  $format !~ /l/) {
	croak __PACKAGE__, "::prop_invmap: Wrong format '$format' for prop_invmap('$prop'); should indicate has lists";
    }

    return (\@invlist, \@invmap, $format, $missing);
}

sub search_invlist {



    my $list_ref = shift;
    my $input_code_point = shift;
    my $code_point = _getcode($input_code_point);

    if (! defined $code_point) {
        carp __PACKAGE__, "::search_invlist: unknown code '$input_code_point'";
        return;
    }

    my $max_element = @$list_ref - 1;

    # Return undef if list is empty or requested item is before the first element.
    return if $max_element < 0;
    return if $code_point < $list_ref->[0];

    # Short cut something at the far-end of the table.  This also allows us to
    # refer to element [$i+1] without fear of being out-of-bounds in the loop
    # below.
    return $max_element if $code_point >= $list_ref->[$max_element];

    use integer;        # want integer division

    my $i = $max_element / 2;

    my $lower = 0;
    my $upper = $max_element;
    while (1) {

        if ($code_point >= $list_ref->[$i]) {

            # Here we have met the lower constraint.  We can quit if we
            # also meet the upper one.
            last if $code_point < $list_ref->[$i+1];

            $lower = $i;        # Still too low.

        }
        else {

            # Here, $code_point < $list_ref[$i], so look lower down.
            $upper = $i;
        }

        # Split search domain in half to try again.
        my $temp = ($upper + $lower) / 2;

        # No point in continuing unless $i changes for next time
        # in the loop.
        return $i if $temp == $i;
        $i = $temp;
    } # End of while loop

    # Here we have found the offset
    return $i;
}


my $UNICODEVERSION;

sub UnicodeVersion {
    unless (defined $UNICODEVERSION) {
	my $versionfh = openunicode("version");
	local $/ = "\n";
	chomp($UNICODEVERSION = <$versionfh>);
	croak __PACKAGE__, "::VERSION: strange version '$UNICODEVERSION'"
	    unless $UNICODEVERSION =~ /^\d+(?:\.\d+)+$/;
    }
    $v_unicode_version = pack "C*", split /\./, $UNICODEVERSION;
    return $UNICODEVERSION;
}


1;
