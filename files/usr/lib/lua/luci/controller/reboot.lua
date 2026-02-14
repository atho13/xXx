module("luci.controller.reboot", package.seeall)

function index()
    entry({"admin", "reboot"}, template("reboot"), _("About"), 100).dependent = false
end
