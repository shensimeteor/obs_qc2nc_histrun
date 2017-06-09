#! /usr/bin/perl
#will find qc_out file in ARCDIR or RUNDIR
#==============================================================================#
# 1. Define inputs
#==============================================================================#
#----------------------------------------------------------------------------#
# 1.1 User's arguments
#----------------------------------------------------------------------------#
if(scalar(@ARGV) < 7) {
    print("Error: 7 arguments needed: <GMID> <MEMBER> <start_cycle> <end_cycle> <domain_list, split by ,> <dir_work> <dir_output_nc>\n");
    exit(1);
}
$GMID= $ARGV[0];
$MEMBER=$ARGV[1];
$START_CYCLE=$ARGV[2];
$END_CYCLE=$ARGV[3];
$DOM_LIST=$ARGV[4]; #0 for non-thin, 1,2,3.. for obs_thin
$DIR_WORK=$ARGV[5]; # #./OBS_QC2NC/$GMID/$MEMBER/cycle/date/domain
$DIR_OUT=$ARGV[6]; #./$cycle/$dom/*nc
@DOMAINS=split(/,/, $DOM_LIST);

#constant parameters
$HOMEDIR=$ENV{HOME};
$GMODDIR="$HOMEDIR/data/GMODJOBS/$GMID";
$ENSPROCS="$ENV{CSH_ARCHIVE}/ncl";
$EXECUTABLE_ARCHIVE ="$HOMEDIR/fddahome/cycle_code/EXECUTABLE_ARCHIVE";
$RUNDIR="$HOMEDIR/data/cycles/$GMID/$MEMBER/";
$ARCDIR="$HOMEDIR/data/cycles/$GMID/archive/$MEMBER/"; #obs/
$CWD=`pwd`;
chomp($CWD);

if (! -e "$GSJOBDIR/ensprocinput.pl") {
    print "\nERROR: Cannot find file $GSJOBDIR/ensprocinput.pl\n\n";
    exit -1;
}else {
    require "$GSJOBDIR/ensprocinput.pl";
}

if (! -e "$ENSPROCS/common_tools.pl") {
    print "\nERROR: Cannnot find file $ENSPROCS/common_tools.pl\n\n";
    exit -1;
}
require "$ENSPROCS/common_tools.pl";

#define parameters
$time_start = 53; $time_end=7; # select 14 minutes obs
$latlon_filename = "latlon.txt";
$thin_nml_dir = "$CWD/thin_namelists/"; #namelist.thin.d?

$cycle=$START_CYCLE;
while($cycle <= $END_CYCLE) {
    $start_date12=&tool_date12_add("${cycle}00", - $CYC_INT, "hour");
    $end_date12="${cycle}00";
    $DIR_QC = "$RUNDIR/RAP_RTFDDA/";
    print("begin cycle $cycle ==================== \n");
    for($date12=$start_date12; $date12<=$end_date12; $date12=&tool_date12_add($date12, 1, "hour")) {
        $date=substr($date12, 0, 10);
        print("of $date -------------");
        $workdir="$DIR_WORK/OBS_QC2NC/$GMID/$MEMBER/$cycle/$date/";
        system("test -d $workdir || mkdir -p $workdir");
        chdir($workdir);
        symlink("$ENSPROCS\/RT_all.obs_trim-merge.USA_ss","$workdir\/RT_all.obs_trim-merge.USA_ss");
        symlink("$GSJOBDIR\/$latlon_filename","$workdir\/latlon.txt");
        
        #find qc_out file
        $valid_m1     = &tool_date12_add($date12, -1, "hour");
        $valid_p1     = &hh_advan_date( $date, 1, "hour");
        $date_time    = &dtstring($date);
        $date_time_m1 = &dtstring($valid_m1);
        $date_time_p1 = &dtstring($valid_p1);
        print "date_time = $DIR_QC/qc_out_${date_time}:00:00.0000; date_time_m1 = qc_out_${date_time_m1}:00:00.0000\n";
        $got_qc=1;
        if (-s "$DIR_QC/qc_out_${date_time_m1}:00:00.0000" &&
                -s "$DIR_QC/qc_out_${date_time}:00:00.0000") {
            system("cat $DIR_QC/qc_out_${date_time_m1}:00:00.0000 $DIR_QC/qc_out_${date_time}:00:00.0000 > hourly.obs");
        } elsif (-s "$DIR_QC/qc_out_${date_time_m1}:00:00.0000" &&
                ! -s "$DIR_QC/qc_out_${date_time}:00:00.0000") {
            system("cp $DIR_QC/qc_out_${date_time_m1}:00:00.0000 hourly.obs");
        } elsif (-s "$DIR_QC/qc_out_${date_time}:00:00.0000" &&
                ! -s "$DIR_QC/qc_out_${date_time_m1}:00:00.0000") {
            system("cp $DIR_QC/qc_out_${date_time}:00:00.0000 hourly.obs");
        } else {
            $got_qc=0;
        }
        if( $got_qc == 0) {
            $DIR_QC="$ARCDIR/obs/";
            if (-s "$DIR_QC/qc_out_${date_time_m1}:00:00.0000" &&
                    -s "$DIR_QC/qc_out_${date_time}:00:00.0000") {
                system("cat $DIR_QC/qc_out_${date_time_m1}:00:00.0000 $DIR_QC/qc_out_${date_time}:00:00.0000 > hourly.obs");
            } elsif (-s "$DIR_QC/qc_out_${date_time_m1}:00:00.0000" &&
                    ! -s "$DIR_QC/qc_out_${date_time}:00:00.0000") {
                system("cp $DIR_QC/qc_out_${date_time_m1}:00:00.0000 hourly.obs");
            } elsif (-s "$DIR_QC/qc_out_${date_time}:00:00.0000" &&
                    ! -s "$DIR_QC/qc_out_${date_time_m1}:00:00.0000") {
                system("cp $DIR_QC/qc_out_${date_time}:00:00.0000 hourly.obs");
            } else{
                print("can not find qc_out file, skip \n");
                next;
            }
        }
        #cut in time/space dims
        system("RT_all.obs_trim-merge.USA_ss hourly.obs $time_start $time_end latlon.txt > /dev/null");
        if ( ! -e "${date}.hourly.obs") {
            print("no ${date}.hourly.obs, failure of running RT_all.obs_trim-merge.USA_ss, skip \n");
            next;
        }
        #do qc2nc & thin (if selected)
        $valid_time_short=$date;
        foreach $domi (@DOMAINS)  {
           print("dom $domi ------");
           $dir_dom="$workdir/d${domi}";
           system("test -d $dir_dom || mkdir -p $dir_dom");
           chdir($dir_dom);
           if($domi > 0) {
               symlink("$EXECUTABLE_ARCHIVE/obs_thin/obs_thinning_v2.0.exe", "obs_thinning.exe");
               symlink("$workdir/${valid_time_short}.hourly.obs", "$dir_dom/${valid_time_short}.hourly.obs");
               #thin
               if( ! -e "$thin_nml_dir/namelist.thin.d${domi}" ) {
                   print " $thin_nml_dir/namelist.thin.d${domi} not exit, skip \n";
                   next;
               }
               symlink("$thin_nml_dir/namelist.thin.d${domi}", "namelist.thin");
               system("./obs_thinning.exe -i ${valid_time_short}.hourly.obs -o thined.hourly.obs < namelist.thin >& thin_d${domi}.log"); 
               #convert
               print "\n  ==> convert data to netCDF\n\n";
               if (-s "thined.hourly.obs") {
                  system("rm -rf ${valid_time_short}.hourly.obs && ln -sf thined.hourly.obs ${valid_time_short}.hourly.obs");
                  system("$EXECUTABLE_ARCHIVE\/QCtoNC.exe ${valid_time_short}.hourly.obs");
                  system("rm -f *.hourly.obs");
               }
           }else{
               system("$EXECUTABLE_ARCHIVE\/QCtoNC.exe ${valid_time_short}.hourly.obs");
               system("rm -rf *hourly.obs");
           }
           $outdir="$DIR_OUT/$cycle/d0${domi}/";
           system("test -d $outdir || mkdir -p $outdir");
           system("mv *nc $outdir/");
        }
    }
}

        

#==============================================================================#
# 5. Subroutines used
#==============================================================================#
#----------------------------------------------------------------------------#
# 5.1 Subroutine dtstring
#----------------------------------------------------------------------------#
sub dtstring {
    my $date_time = $_[0]; # input arg in YYYYMMDDHH<MN<SS>>
        my $yr = substr($date_time,0,4);
    my $mo = substr($date_time,4,2);
    my $dy = substr($date_time,6,2);
    my $hr = substr($date_time,8,2);
    my $string = "${yr}-${mo}-${dy}_${hr}";
    return $string;
}
1;
