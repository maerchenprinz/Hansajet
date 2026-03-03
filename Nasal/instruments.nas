#########################################
## ADF-1
#########################################
var addfreqs1 = func {
 var subband1 = getprop("Hansajet/ADF/adf1_Subband");
 var finetune1 = getprop("Hansajet/ADF/adf1_TuneKnob");
 var finalfreq1 = finetune1 + subband1 ;
 setprop("instrumentation/adf[0]/frequencies/selected-khz", finalfreq1);
 setprop("instrumentation/adf[1]/frequencies/selected-khz", finalfreq1);
}
 setlistener("Hansajet/ADF/adf1_Subband", addfreqs1, 1, 0);
 setlistener("Hansajet/ADF/adf1_TuneKnob", addfreqs1, 1, 0);

var addfreqs2 = func {
 var subband2 = getprop("Hansajet/ADF/adf2_Subband");
 var finetune2 = getprop("Hansajet/ADF/adf2_TuneKnob");
 var finalfreq2 = finetune2 + subband2 ;
 setprop("instrumentation/adf2[0]/frequencies/selected-khz", finalfreq2);
 setprop("instrumentation/adf2[1]/frequencies/selected-khz", finalfreq2);
}
 setlistener("Hansajet/ADF/adf2_Subband", addfreqs2, 1, 0);
 setlistener("Hansajet/ADF/adf2_TuneKnob", addfreqs2, 1, 0);



#########################################
## Audio Panel Gabler 346B-X
#########################################
var Device = "ALL";
var CurrentAudioPanelVol = "0";
var VolADF1 = "0";
var AudioOutput = func(Device) {
	var ViewNumber = getprop("/sim/current-view/view-number-raw");
	var CurrentAudioPanelVol = getprop("Hansajet/AudioPanel/kn_audiopanel_Volume_" ~ ViewNumber ~ "");

	if ((Device == "ADF-1") or (Device == "ALL")) {
		var VolADF1 = getprop("Hansajet/ADF/adf1_Volume");
		var AudibleADF1 = getprop("Hansajet/AudioPanel/sw_ADF-1_" ~ ViewNumber ~ "");
		var VolADF1out = AudibleADF1 * CurrentAudioPanelVol * VolADF1 ;
		setprop("/instrumentation/adf/volume-norm", VolADF1out) ;
	}
	if ((Device == "ADF-2") or (Device == "ALL")) {
		var VolADF2 = getprop("Hansajet/ADF/adf2_Volume");
		var AudibleADF2 = getprop("Hansajet/AudioPanel/sw_ADF-2_" ~ ViewNumber ~ "");
		var VolADF2out = AudibleADF1 * CurrentAudioPanelVol * VolADF2 ;
		setprop("/instrumentation/adf2/volume-norm", VolADF2out) ;
	}

	if ((Device == "COMM-1") or (Device == "ALL")) {
		var VolCOMM1 = getprop("Hansajet/COMM/comm1_Volume");
		var AudibleCOMM1 = getprop("Hansajet/AudioPanel/sw_VHF-1_" ~ ViewNumber ~ "");
		var VolCOMM1out = AudibleCOMM1 * CurrentAudioPanelVol * VolCOMM1 ;
		setprop("/instrumentation/comm/volume", VolCOMM1out) ;
	}
	if ((Device == "NAV-1") or (Device == "ALL")) {
		var VolNAV1 = getprop("Hansajet/NAV/nav1_kn_Volume");
		var AudibleNAV1 = getprop("Hansajet/AudioPanel/sw_NAV-1_" ~ ViewNumber ~ "");
		var VolNAV1out = AudibleNAV1 * CurrentAudioPanelVol * VolNAV1 ;
		setprop("/instrumentation/nav/volume", VolNAV1out) ;
	}
}
 setlistener("/sim/current-view/view-number-raw", func {AudioOutput(Device = "ALL")}, 1, 0);
 setlistener("/Hansajet/AudioPanel/kn_audiopanel_Volume_0", func {AudioOutput(Device = "ALL")}, 1, 0);

#########################################
## NAV-1 (Collins 313N-3D)
#########################################
var NAV1KnobMode = func {
 var ModeNav1 = getprop("Hansajet/NAV/nav1_kn_Mode");
	if (ModeNav1 != 0) {
	var NAV1IdentAudible = 1 ;
	var NAV1IdentVolume = 1.0 ;
	}
	else {
	var NAV1IdentAudible = 0 ;
	var NAV1IdentVolume = 0.0 ;
	}
	setprop("/instrumentation/nav/loc/ident-enabled", int(NAV1IdentAudible)) ;
	setprop("/instrumentation/nav/loc/ident-volume", NAV1IdentVolume) ;
}
 setlistener("Hansajet/NAV/nav1_kn_Mode", NAV1KnobMode, 1, 0);
