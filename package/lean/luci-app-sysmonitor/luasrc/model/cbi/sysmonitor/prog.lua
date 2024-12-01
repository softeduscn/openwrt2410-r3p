
local appname = "sysmonitor"
bin = require "nixio".bin
fs = require "nixio.fs"
sys = require "luci.sys"
uci = require"luci.model.uci".cursor()
util = require "luci.util"
datatypes = require "luci.cbi.datatypes"
jsonc = require "luci.jsonc"
i18n = require "luci.i18n"

function url(...)
	local url = string.format("admin/sys/%s", appname)
	local args = { ... }
	for i, v in pairs(args) do
		if v ~= "" then
			url = url .. "/" .. v
		end
	end
	return require "luci.dispatcher".build_url(url)
end

function is_js_luci()
	return sys.call('[ -f "/www/luci-static/resources/uci.js" ]') == 0
end

function set_apply_on_parse(map)
	if is_js_luci() == true then
		map.apply_on_parse = false
		map.on_after_apply = function(self)
			if self.redirect then
				os.execute("sleep 1")
				luci.http.redirect(self.redirect)
			end
		end
	end
end
show=luci.sys.exec("cat /usr/lib/lua/luci/view/sysmonitor/prog.htm|grep block|wc -l")
m = Map("sysmonitor",translate("General Settings"))
set_apply_on_parse(m)

s = m:section(TypedSection, "sysmonitor")
if tonumber(show) == 1 then
	button='APPHiden'
else
	button='APPShow'
end	
--s.description = '<table><style>.button1 {-webkit-transition-duration: 0.4s;transition-duration: 0.4s;padding: 1px 3px;text-align: center;background-color: white;color: black;border: 2px solid #4CAF50;border-radius:5px;}.button1:hover {background-color: #4CAF50;color: white;}.button1 {font-size: 11px;}</style><tr><td><button class="button1"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=ShowProgsys1=&redir=general">'..translate(button)..'</a></button></td></tr></table>'

s.anonymous = true


m:append(Template("sysmonitor/prog"))

s = m:section(TypedSection, "prog_list", "", translate(""))
s.addremove = true
s.anonymous = true
s.sortable = true
s.template = "cbi/tblsection"
s.extedit = url("general", "%s")
function s.create(e, t)
	local id = TypedSection.create(e, t)
	luci.http.redirect(e.extedit:format(id))
end

o = s:option(Flag, "enabled", translate("Enable"))
o.width = "5%"
o.rmempty = true

o = s:option(Value, "name", translate("Name"))
o.width = "16%"
o.rmempty = true

o = s:option(Value, "path", translate("Path + Main"))
o.width = "auto"
o.rmempty = true

o = s:option(Value, "program", translate("Program name"))
o.width = "15%"
o.rmempty = true

o = s:option(Value, "cycle", translate("Run cycle(s)"))
o.width = "8%"
o.rmempty = true

--o = s:option(Value, "first", translate("First run cycle(s)"))
--o.width = "10%"
--o.rmempty = true

return m
