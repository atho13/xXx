module("luci.controller.shutdown",package.seeall)

function index()
	entry({"admin","system","poweroff"},template("shutdown"),_("Shutdown"),100)
	entry({"admin","system","poweroff","call"},call("action_poweroff"))
end

function action_poweroff()
luci.sys.exec("/sbin/poweroff")
end