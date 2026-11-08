# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "MAX_BURST_LEN" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TIMEOUT_CYCLES" -parent ${Page_0}


}

proc update_PARAM_VALUE.MAX_BURST_LEN { PARAM_VALUE.MAX_BURST_LEN } {
	# Procedure called to update MAX_BURST_LEN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_BURST_LEN { PARAM_VALUE.MAX_BURST_LEN } {
	# Procedure called to validate MAX_BURST_LEN
	return true
}

proc update_PARAM_VALUE.TIMEOUT_CYCLES { PARAM_VALUE.TIMEOUT_CYCLES } {
	# Procedure called to update TIMEOUT_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TIMEOUT_CYCLES { PARAM_VALUE.TIMEOUT_CYCLES } {
	# Procedure called to validate TIMEOUT_CYCLES
	return true
}


proc update_MODELPARAM_VALUE.MAX_BURST_LEN { MODELPARAM_VALUE.MAX_BURST_LEN PARAM_VALUE.MAX_BURST_LEN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_BURST_LEN}] ${MODELPARAM_VALUE.MAX_BURST_LEN}
}

proc update_MODELPARAM_VALUE.TIMEOUT_CYCLES { MODELPARAM_VALUE.TIMEOUT_CYCLES PARAM_VALUE.TIMEOUT_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TIMEOUT_CYCLES}] ${MODELPARAM_VALUE.TIMEOUT_CYCLES}
}

