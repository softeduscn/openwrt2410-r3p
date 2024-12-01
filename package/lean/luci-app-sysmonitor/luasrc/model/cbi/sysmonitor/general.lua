local m

m = Map("sysmonitor",translate("General Settings"))

s = m:section(TypedSection, "sysmonitor")
s.anonymous = true

o=s:option(Flag,"syslog", translate("SYSLOG Enable"))
o.rmempty=false

o = s:option(Value, "vpnsw", translate("VPN switch time(s)"))
o.rmempty = false

--o = s:option(Value, "chkprog", translate("Check delay_prog time(s)"))
--o.rmempty = false

o = s:option(Value, translate("firmware"), translate("Firmware Address"))
o.rmempty = false

return m
