#!/bin/ksh -x

###############################################################
## Abstract:
## Archive driver script
## RUN_ENVIR : runtime environment (emc | nco)
## HOMEgfs   : /full/path/to/workflow
## EXPDIR : /full/path/to/config/files
## CDATE  : current analysis date (YYYYMMDDHH)
## CDUMP  : cycle name (gdas / gfs)
## PDY    : current date (YYYYMMDD)
## cyc    : current cycle (HH)
###############################################################

###############################################################
# Source FV3GFS workflow modules
. $HOMEgfs/ush/load_fv3gfs_modules.sh
status=$?
[[ $status -ne 0 ]] && exit $status

###############################################################
# Source relevant configs
configs="base arch"
for config in $configs; do
    . $EXPDIR/config.${config}
    status=$?
    [[ $status -ne 0 ]] && exit $status
done

# ICS are restarts and always lag INC by $assim_freq hours
ARCHINC_CYC=$ARCH_CYC
ARCHICS_CYC=$((ARCH_CYC-assim_freq))
if [ $ARCHICS_CYC -lt 0 ]; then
    ARCHICS_CYC=$((ARCHICS_CYC+24))
fi

# CURRENT CYCLE
APREFIX="${CDUMP}.t${cyc}z."
ASUFFIX=${ASUFFIX:-$SUFFIX}

if [ $ASUFFIX = ".nc" ]; then
   format="netcdf"
else
   format="nemsio"
fi


# Realtime parallels run GFS MOS on 1 day delay
# If realtime parallel, back up CDATE_MOS one day
CDATE_MOS=$CDATE
if [ $REALTIME = "YES" ]; then
    CDATE_MOS=$($NDATE -24 $CDATE)
fi
PDY_MOS=$(echo $CDATE_MOS | cut -c1-8)

###############################################################
# Archive online for verification and diagnostics
###############################################################

COMIN=${COMINatmos:-"$ROTDIR/$CDUMP.$PDY/$cyc/atmos"}
cd $COMIN

[[ ! -d $ARCDIR ]] && mkdir -p $ARCDIR
$NCP ${APREFIX}gsistat $ARCDIR/gsistat.${CDUMP}.${CDATE}
$NCP ${APREFIX}pgrb2.1p00.anl $ARCDIR/pgbanl.${CDUMP}.${CDATE}.grib2

# Archive 1 degree forecast GRIB2 files for verification
if [ $CDUMP = "gfs" ]; then
    fhmax=$FHMAX_GFS
    fhr=0
    while [ $fhr -le $fhmax ]; do
        fhr2=$(printf %02i $fhr)
        fhr3=$(printf %03i $fhr)
        $NCP ${APREFIX}pgrb2.1p00.f$fhr3 $ARCDIR/pgbf${fhr2}.${CDUMP}.${CDATE}.grib2
        (( fhr = $fhr + $FHOUT_GFS ))
    done
fi
if [ $CDUMP = "gdas" ]; then
    flist="000 003 006 009"
    for fhr in $flist; do
        fname=${APREFIX}pgrb2.1p00.f${fhr}
        fhr2=$(printf %02i $fhr)
        $NCP $fname $ARCDIR/pgbf${fhr2}.${CDUMP}.${CDATE}.grib2
    done
fi

if [ -s avno.t${cyc}z.cyclone.trackatcfunix ]; then
    PLSOT4=`echo $PSLOT|cut -c 1-4 |tr '[a-z]' '[A-Z]'`
    cat avno.t${cyc}z.cyclone.trackatcfunix | sed s:AVNO:${PLSOT4}:g  > ${ARCDIR}/atcfunix.${CDUMP}.$CDATE
    cat avnop.t${cyc}z.cyclone.trackatcfunix | sed s:AVNO:${PLSOT4}:g  > ${ARCDIR}/atcfunixp.${CDUMP}.$CDATE
fi

if [ $CDUMP = "gdas" -a -s gdas.t${cyc}z.cyclone.trackatcfunix ]; then
    PLSOT4=`echo $PSLOT|cut -c 1-4 |tr '[a-z]' '[A-Z]'`
    cat gdas.t${cyc}z.cyclone.trackatcfunix | sed s:AVNO:${PLSOT4}:g  > ${ARCDIR}/atcfunix.${CDUMP}.$CDATE
    cat gdasp.t${cyc}z.cyclone.trackatcfunix | sed s:AVNO:${PLSOT4}:g  > ${ARCDIR}/atcfunixp.${CDUMP}.$CDATE
fi

if [ $CDUMP = "gfs" ]; then
    $NCP storms.gfso.atcf_gen.$CDATE      ${ARCDIR}/.
    $NCP storms.gfso.atcf_gen.altg.$CDATE ${ARCDIR}/.
    $NCP trak.gfso.atcfunix.$CDATE        ${ARCDIR}/.
    $NCP trak.gfso.atcfunix.altg.$CDATE   ${ARCDIR}/.

    mkdir -p ${ARCDIR}/tracker.$CDATE/$CDUMP
    blist="epac natl"
    for basin in $blist; do
	cp -rp $basin                     ${ARCDIR}/tracker.$CDATE/$CDUMP
    done
fi

# Archive required gaussian gfs forecast files for Fit2Obs
if [ $CDUMP = "gfs" -a $FITSARC = "YES" ]; then
    VFYARC=${VFYARC:-$ROTDIR/vrfyarch}
    [[ ! -d $VFYARC ]] && mkdir -p $VFYARC
    mkdir -p $VFYARC/${CDUMP}.$PDY/$cyc
    prefix=${CDUMP}.t${cyc}z
    fhmax=${FHMAX_FITS:-$FHMAX_GFS}
    fhr=0
    while [[ $fhr -le $fhmax ]]; do
	fhr3=$(printf %03i $fhr)
	sfcfile=${prefix}.sfcf${fhr3}${ASUFFIX}
	sigfile=${prefix}.atmf${fhr3}${ASUFFIX}
	$NCP $sfcfile $VFYARC/${CDUMP}.$PDY/$cyc/
	$NCP $sigfile $VFYARC/${CDUMP}.$PDY/$cyc/
	(( fhr = $fhr + 6 ))
    done
fi


###############################################################
# Clean up previous cycles; various depths
# PRIOR CYCLE: Leave the prior cycle alone
GDATE=$($NDATE -$assim_freq $CDATE)

# PREVIOUS to the PRIOR CYCLE
GDATE=$($NDATE -$assim_freq $GDATE)
gPDY=$(echo $GDATE | cut -c1-8)
gcyc=$(echo $GDATE | cut -c9-10)

# Remove the TMPDIR directory
COMIN="$RUNDIR/$GDATE"
[[ -d $COMIN ]] && rm -rf $COMIN

if [[ "${DELETE_COM_IN_ARCHIVE_JOB:-YES}" == NO ]] ; then
    exit 0
fi

# Step back every assim_freq hours and remove old rotating directories 
# for successful cycles (defaults from 24h to 120h).  If GLDAS is
# active, retain files needed by GLDAS update.  Independent of GLDAS, 
# retain files needed by Fit2Obs
DO_GLDAS=${DO_GLDAS:-"NO"}
GDATEEND=$($NDATE -${RMOLDEND:-24}  $CDATE)
GDATE=$($NDATE -${RMOLDSTD:-120} $CDATE)
GLDAS_DATE=$($NDATE -96 $CDATE)
RTOFS_DATE=$($NDATE -48 $CDATE)
while [ $GDATE -le $GDATEEND ]; do
    gPDY=$(echo $GDATE | cut -c1-8)
    gcyc=$(echo $GDATE | cut -c9-10)
    COMIN="$ROTDIR/${CDUMP}.$gPDY/$gcyc/atmos"
    COMINwave="$ROTDIR/${CDUMP}.$gPDY/$gcyc/wave"
    COMINrtofs="$ROTDIR/rtofs.$gPDY"
    if [ -d $COMIN ]; then
        rocotolog="$EXPDIR/logs/${GDATE}.log"
	if [ -f $rocotolog ]; then
            testend=$(tail -n 1 $rocotolog | grep "This cycle is complete: Success")
            rc=$?
            if [ $rc -eq 0 ]; then
                if [ -d $COMINwave ]; then rm -rf $COMINwave ; fi
                if [ -d $COMINrtofs -a $GDATE -lt $RTOFS_DATE ]; then rm -rf $COMINrtofs ; fi
                if [ $CDUMP != "gdas" -o $DO_GLDAS = "NO" -o $GDATE -lt $GLDAS_DATE ]; then 
		    if [ $CDUMP = "gdas" ]; then
                        for file in `ls $COMIN |grep -v prepbufr |grep -v cnvstat |grep -v atmanl.nc`; do
                            rm -rf $COMIN/$file
                        done
		    else
			rm -rf $COMIN
		    fi
                else
		    if [ $DO_GLDAS = "YES" ]; then
			for file in `ls $COMIN |grep -v sflux |grep -v RESTART |grep -v prepbufr |grep -v cnvstat |grep -v atmanl.nc`; do
                            rm -rf $COMIN/$file
			done
			for file in `ls $COMIN/RESTART |grep -v sfcanl `; do
                            rm -rf $COMIN/RESTART/$file
			done
		    else
                        for file in `ls $COMIN |grep -v prepbufr |grep -v cnvstat |grep -v atmanl.nc`; do
                            rm -rf $COMIN/$file
                        done
		    fi
                fi
            fi
	fi
    fi

    # Remove any empty directories
    if [ -d $COMIN ]; then
        [[ ! "$(ls -A $COMIN)" ]] && rm -rf $COMIN
    fi

    if [ -d $COMINwave ]; then
        [[ ! "$(ls -A $COMINwave)" ]] && rm -rf $COMINwave
    fi

    # Remove mdl gfsmos directory
    if [ $CDUMP = "gfs" ]; then
	COMIN="$ROTDIR/gfsmos.$gPDY"
	if [ -d $COMIN -a $GDATE -lt $CDATE_MOS ]; then rm -rf $COMIN ; fi
    fi

    GDATE=$($NDATE +$assim_freq $GDATE)
done

# Remove archived gaussian files used for Fit2Obs in $VFYARC that are 
# $FHMAX_FITS plus a delta before $CDATE.  Touch existing archived 
# gaussian files to prevent the files from being removed by automatic 
# scrubber present on some machines.

if [ $CDUMP = "gfs" ]; then
    fhmax=$((FHMAX_FITS+36))
    RDATE=$($NDATE -$fhmax $CDATE)
    rPDY=$(echo $RDATE | cut -c1-8)
    COMIN="$VFYARC/$CDUMP.$rPDY"
    [[ -d $COMIN ]] && rm -rf $COMIN

    TDATE=$($NDATE -$FHMAX_FITS $CDATE)
    while [ $TDATE -lt $CDATE ]; do
        tPDY=$(echo $TDATE | cut -c1-8)
        tcyc=$(echo $TDATE | cut -c9-10)
        TDIR=$VFYARC/$CDUMP.$tPDY/$tcyc
        [[ -d $TDIR ]] && touch $TDIR/*
        TDATE=$($NDATE +6 $TDATE)
    done
fi

# Remove $CDUMP.$rPDY for the older of GDATE or RDATE
GDATE=$($NDATE -${RMOLDSTD:-120} $CDATE)
fhmax=$FHMAX_GFS
RDATE=$($NDATE -$fhmax $CDATE)
if [ $GDATE -lt $RDATE ]; then
    RDATE=$GDATE
fi
rPDY=$(echo $RDATE | cut -c1-8)
COMIN="$ROTDIR/$CDUMP.$rPDY"
[[ -d $COMIN ]] && rm -rf $COMIN


###############################################################
exit 0
