#!/usr/bin/env perl
#The Metagenomic Assembly, Genomic Recovery and Assembly Independent Mapping Tool
#main MATAFILER routine
#ex
#./MATAFILER.pl map2tar /g/scb/bork/hildebra/SNP/test/refCtg.fasta,/g/scb/bork/hildebra/SNP/test/refCtg.fasta test1,test2
#./MATAFILER.pl map2tar /g/bork3/home/hildebra/results/TEC2/v5/TEC2.MM4.BEE.GF.rn.fa TEC2
#./MATAFILER.pl map2tar /g/bork3/home/hildebra/results/prelimGenomes/TEC3/MM3.TEC3.scaffs.fna,/g/bork3/home/hildebra/results/prelimGenomes/TEC3/TEC3ref.fasta,/g/bork3/home/hildebra/results/prelimGenomes/TEC4/MM3.TEC4.scaffs.fna,/g/bork3/home/hildebra/results/prelimGenomes/TEC4/TEC4ref.fasta,/g/bork3/home/hildebra/results/prelimGenomes/TEC5/MM4.TEC5.scaffs.fna,/g/bork3/home/hildebra/results/prelimGenomes/TEC5/TEC5ref.fasta,/g/bork3/home/hildebra/results/prelimGenomes/TEC6/MM29.TEC6.scaffs.fna,/g/bork3/home/hildebra/results/prelimGenomes/TEC6/TEC6ref.fasta TEC3,TEC3r,TEC4,TEC4r,TEC5,TEC5r,TEC6,TEC6r
#/g/bork5/hildebra/results/TEC2/v5/T6/TEC6.ctgs.rn.fna
#./MATAFILER.pl map2DB /g/bork3/home/hildebra/DB/freeze11/freeze11.genes.representatives.fa frz11; ./MATAFILER.pl map2DB /g/bork3/home/hildebra/DB/GeneCats/Tara/Tara.fna Tara; ./TAMOC.pl map2DB /g/bork3/home/hildebra/DB/GeneCats/IGC/1000RefGeneCat.fna IGC
#./MATAFILER.pl map2tar /g/bork3/home/hildebra/results/TEC2/v5/TEC2.MM4.BEE.GF.rn.fa,/g/bork3/home/hildebra/results/TEC2/v5/T6/TEC6.ctgs.rn.fna T2d,T6d

# GGC279

use warnings;
use strict;
use File::Basename;
use Cwd 'abs_path';
use POSIX;
use Getopt::Long qw( GetOptions );

use Mods::GenoMetaAss qw(readMap qsubSystem emptyQsubOpt findQsubSys readFastHD prefix_find gzipopen readFasta writeFasta);
use Mods::IO_Tamoc_progs qw(getProgPaths setConfigFile jgi_depth_cmd inputFmtSpades inputFmtMegahit createGapFillopt  buildMapperIdx);
use vars qw($CONFIG_FILE);
use Mods::TamocFunc qw (getSpecificDBpaths getFileStr);
use Mods::phyloTools qw(fixHDs4Phylo);


sub help; sub annoucnce_MATAFILER;
sub seedUnzip2tmp; sub clean_tmp; sub cleanInput; #unzipping reads; removing these at later stages ; remove tmp dirs
sub readG2M; sub check_matesL;

sub mapReadsToRef;  sub bamDepth;
sub ReadsFromMapping;

sub spadesAssembly; #main Assembler
sub megahitAssembly; #secondary Assembler
sub createPsAssLongReads; #pseudo assembler
sub scaffoldCtgs;  #scaffold assemblies / external contigs
sub GapFillCtgs;   #post scaffolding using reads from samples
sub filterSizeFasta;
sub sdmClean; sub check_sdm_loc; #qual filter reads
sub mergeReads; #merge reads via flash
sub SEEECER; 
sub run_prodigal_augustus; sub run_prodigal; #gene prediction
#sub randStr; 
sub contigStats;sub smplStats;
sub adaptSDMopt;#sub readMap; sub qsubSystem;
sub checkDrives;sub bam2cram;
sub mocat_reorder; sub postSubmQsub;
sub detectRibo; 
sub runOrthoPlacement;
sub runDiamond; sub DiaPostProcess; sub IsDiaRunFinished;
sub nopareil; sub calcCoverage;
sub prepKraken;sub krakHSap; sub krakenTaxEst;
sub d2metaDist;
sub metphlanMapping; sub mergeMP2Table;
sub mOTU2Mapping; sub mergeMotu2Table; sub prepMOTU2;
sub genoSize;

#bjobs | awk '$3=="CDDB" {print $1}' |xargs bkill
#bjobs | grep 'dWXmOT' | cut -f11 -d' ' | xargs -t -i bkill {}
#squ | grep _UZ | cut -f11 -d' ' | xargs  -t -i scancel {}
#bhosts | cut -f1 -d' ' | grep -v HOST_NAME | xargs -t -i ssh {} 'killall -u hildebra'
#hosts=`bhosts | grep ok | cut -d" " -f 1 | grep compute | tr "\\n" ","`; pdsh -w $hosts "rm -rf /tmp/hildebra"

my $MATFILER_ver = 0.16;

#----------------- defaults ----------------- 
my $rawFileSrchStr1 = '.*1\.f[^\.]*q\.gz$';
my $rawFileSrchStr2 = '.*2\.f[^\.]*q\.gz$';
my $rawFileSrchStrSingl = "";
my $rawFileSrchStrXtra1= '.*1_sequence\.f[^\.]*q\.gz$';
my $rawFileSrchStrXtra2= '.*2_sequence\.f[^\.]*q\.gz$';
my $submSytem = "";

my %sdm_opt; #empty object that can be used to modify default sdm parameters
my $tmpSdmminSL=0; my $tmpSdmmaxSL=0;

my $mateInsertLength =20000; #controls expected mate insert size , import for bowtie2 mappings
my %jmp=();
my $logDir = "";
my $sharedTmpDirP = ""; #e.g. /scratch/MATAFILER/
#$sharedTmpDirP = "/g/scb/bork/hildebra/tmp/" if (`hostname` !~ m/submaster/);
my $nodeTmpDirBase = "";#/tmp/MATAFILER/
my $nodeHDDspace = 30720;
my $baseDir = ""; my $baseOut = "";
my $mapFile = ""; my $baseID = "";
my $configFile = "";


#databases empty structs --------------------------
my $globalKraTaxkDB = "";
my %globalRiboDependence =(DBcp => "");
my %globalDiamondDependence = (CZy=>"",MOH=>"",NOG=>"",ABR=>"",ABRc=>"",KGB=>"",KGE=>"",ACL=>"",KGM=>"", PTV=>"", PAB => "");

#more specific control: unfiniRew=rewrite unfinished sample dir; $redoCS = redo ContigStats completely; 
#removeInputAgain=remove unzipped files from scratch, after sdm; remove_reads_tmpDir = leave cleaned reads on scratch after everything finishes
my $unfiniRew=0; my $redoCS=0; my $removeInputAgain=1; my $remove_reads_tmpDir=0;
my $silent = 0;
my $redoFails = 0;

my $readsRpairs=-1; #are reads given in pairs? default: -1 = no clue
my $useTrimomatic=1;
my $prefSinglFQgreps = 0; #if grep of files (rawSrchString) has multi assignments, which grep to trust more?
my $unzipCores = 3;
my $splitFastaInput = 0; #assembly as input..
my $importMocat = 0; my  $mocatFiltPath = "reads.screened.screened.adapter.on.hg19.solexaqa/"; 
my $gzipSDMOut = 1;#zip sdm filtered files
my $sdmProbabilisticFilter=1;
my $alwaysDoStats = 1; 
my $rmScratchTmp=0;#Default; extremely important option as this adds a lot of overhead and scratch usage space, but reduces later overhead a lot and makes IO more stable
my $humanFilter = 1; #use kraken to filter out human reads
my $unpackZip = 0; #only goes through with read filtering, needed to get files for luis
my $filterFromSource=0;
my $DoMetaPhlan = 0; my $metaPhl2FailCnts=0; #non-asembly based tax + functional assignments
my $DoMOTU2 = 0;my $mOTU2FailCnts=0; 
my $DoRibofind = 0; my $doRiboAssembl = 0; my $RedoRiboFind = 0; my $riboFindFailCnts=0; #ITS/SSU/LSU detection
my $riboLCAmaxRds = 50000; #set to 50k by default, larger gets slower too fast
my $riboStoreRds = 0; #store original sequence for later work on them?

my $RedoRiboAssign = 0; my $checkRiboNonEmpty=0; 
my $RedoRiboThatFailed=  0;#this option is used for debugging: redo ribo completely, if something failed in run
my $DoBinning = 0;
my $doReadMerge = 0;
my $DoAssembly = 1;  my $SpadesAlwaysHDDnode = 1;my $spadesBayHam = 0; my $useSDM = 2;my $spadesMisMatCor = 0; my $redoAssembly =0 ;
my $map2Assembly = 0; my $SaveUnalignedReads=0;
my $bwtIdxAssMem = 40; #total mem in GB, not core adjusted, for building index from assembly
my $doBam2Cram= 1; my $redoAssMapping=0;
my $DoJGIcoverage = 0; #only required for metabat binning, not required any longer..
my $DoNP=0; #non-pareil
my $doDateFileCheck = 0; #very specific option for Moh's reads that were of different dates..
my $DoDiamond = 0; my $rewriteDiamond =0; my $redoDiamondParse = 0; #redoes matching of reads; redoes interpretation
my $MapperProg = 1;#1=bowtie2, 2=bwa
my $DO_EUK_GENE_PRED = 0;
my $DoCalcD2s = 0; 
my $calcOrthoPlacement=0; #Jaime's 6 frame translation and hmmersearch (AB production)
my $DoKraken = 0; my $RedoKraken = 0; my $KrakTaxFailCnts=0;
my $pseudoAssembly = 0; #in case no assembly is possible (soil single reads), just filter for reads X long 
my $DoFreeGlbTmp = 0; my $defaultReadLength = 100;
my $maxReqDiaDB = 6; #max number of databases supported by METAFILER
my $reqDiaDB = "";#,NOG,MOH,ABR,ABRc,ACL,KGM,PTV,PAB";#,ACL,KGM,ABRc,CZy";#"NOG,CZy"; #"NOG,MOH,CZy,ABR,ABRc,ACL,KGM"   #old KGE,KGB
#program configuration
my $Assembly_Cores=48; my $Assembly_Memory = 200; #in GB
my $Spades_HDspace = 100; #required space in GB
my $Assembly_Kmers = "27,33,55,71";
my $bwt_Cores = 12; my $map_DoConsensus = 1; my $doRmDup = 1; #mapping cores; ??? ; remove Dups (can be costly if many ref seqs present)
my $diaEVal = "1e-7"; my $dia_Cores = 16; my $krakenCores = 9;
my $DiaMinAlignLen = 20; my $DiaMinFracQueryCov = 0.1; my $DiaPercID =40;
my $MappingMem = "3G";
my $oldStylFolders=0; #0=smpl name as out folder; 1=inputdir as out foler (legacy)
my $DoGenoSize=0;

#----------- map all reads to a specific reference - options ---------
my $map2ndDeps= "";my $mapModeActive=0; my $mapModeCovDo=1;#get the coverage per gene etc

my $mapModeTogether = 1; my %map2ndTogRefDB;
my $mapModeDecoyDo=1;my %make2ndMapDecoy;my $rewrite2ndMap = 0;
my @bwt2outD =(); my @DBbtRefX = (); my @DBbtRefGFF=(); #my $bwt2Name=""; 
my $refDBall; my $bwt2NameAll ;

#control broad flow
my $from=0; my $to=100000;

my $doSubmit=1; 
my $rewrite=0;


GetOptions(
	"help|?" => \&help,
	"map=s"      => \$mapFile,
	"config=s" => \$configFile,
	#flow related
	"rm_tmpdir_reads=i" => \$remove_reads_tmpDir,
	"rm_tmpInput=i" => \$removeInputAgain,
	"globalTmpDir=s" => \$sharedTmpDirP,#absolute path to global shared tmp dir (like a scratch dir)
	"nodeTmpDir=s" => \$nodeTmpDirBase,#absolute path to tmp dir on local HDD of each executing node
	"nodeHDDspace=s" => \$nodeHDDspace,#HDD tmp space to be requested for each node. Some systems don't support this
	"legacyFolders=i" => \$oldStylFolders, #legacy option, controls if output folders will use the read dir as name (1) or the name in the mapping file (0). Default=0
	"submSystem=s" => \$submSytem,  #qsub,SGE,bsub,LSF
	"submit=i" => \$doSubmit,
	"from=i" => \$from,
	"to=i" => \$to,
	"useTrimomatic=i" => \$useTrimomatic, #rm adapter seq from input reads
	#"rmRawRds=i" => \$DoFreeGlbTmp, #rm raw sequences, once all jobs have finished <-- redundant with reduceScratchUse
	"silent" => \$silent,
	"reduceScratchUse=i" => \$rmScratchTmp, 
	"redoFails=i" =>\$redoFails, #if any step of requested analysis failed, just redo everything (extraction etc)
	#input FQ related
	"inputFQregex1=s" => \$rawFileSrchStr1,
	"inputFQregex2=s" => \$rawFileSrchStr2,
	"inputFQregexSingle=s" => \$rawFileSrchStrSingl,
	"inputFQregexTrustSingle=i" => \$prefSinglFQgreps , #if grep of files (rawSrchString) has multi assignments, which grep to trust more?
	"splitFastaInput=i" => \$splitFastaInput,
	"mergeReads=i" => \$doReadMerge,
	"ProbRdFilter=i" => \$sdmProbabilisticFilter,
	"pairedReadInput=i" => \$readsRpairs, #determines if read pairs are expected in each in dir
	"inputReadLength=i" => \$defaultReadLength,
	"filterHumanRds=i" => \$humanFilter,
	"onlyFilterZip=i" => \$unpackZip,
	"mocatFiltered=i" => \$importMocat,
	#sdm related
	"minReadLength=i" => \$tmpSdmminSL,
	"maxReadLength=i" => \$tmpSdmmaxSL,
	#assembly related
	"spadesCores=i" => \$Assembly_Cores,
	"spadesMemory=i" => \$Assembly_Memory, #in GB
	"spadesKmers=s" => \$Assembly_Kmers, #comma delimited list
	"binSpeciesMG=i" => \$DoBinning,
	"reAssembleMG=i" => \$redoAssembly,
	"assembleMG=i" => \$DoAssembly, #1=Spades, 2=MegaHIT
	#mapping related (asselmbly)
	"remap2assembly=i" => \$redoAssMapping,
	"JGIdepths=i" => \$DoJGIcoverage,
	"mapReadsOntoAssembly=i" => \$map2Assembly ,  #map original reads back on assembly, to estimate abundance etc
	"saveReadsNotMap2Assembly=i" => \$SaveUnalignedReads,
	#gene prediction on assembly
	"predictEukGenes=i" => \$DO_EUK_GENE_PRED,#severely limits total predicted gene amount (~25% of total genes)
	#mapping
	"mappingCoverage=i" => \$mapModeCovDo,
	"mappingMem=i" => \$MappingMem, #mem for bwa/bwt2 in GB
	"rmDuplicates=i" => \$doRmDup,
	"mappingCores=i" => \$bwt_Cores,
	#map2tar / map2DB
	"decoyMapping=i" => \$mapModeDecoyDo,
	"competitive2ndmap" => \$mapModeTogether,
	"ref=s" => \$refDBall,
	"mapnms=s" => \$bwt2NameAll, #name for this final files
	"reado2ndmap=i" => \$rewrite2ndMap,
	#functional profiling (diamond)
	"profileFunct=i"=> \$DoDiamond,
	"reParseFunct=i" => \$redoDiamondParse,
	"reProfileFunct=i" => \$rewriteDiamond,
	"diamondCores=i" => \$dia_Cores,
	"DiaParseEvals=s" => \$diaEVal, #evalues at which to accept hits to func database
	"DiaMinAlignLen=i" => \$DiaMinAlignLen,
	"DiaMinFracQueryCov=f" =>  \$DiaMinFracQueryCov,
	"DiaPercID=i" => \$DiaPercID,
	"diamondDBs=s" => \$reqDiaDB,#NOG,MOH,ABR,ABRc,ACL,KGM,CZy,PTV,PAB
	#functional profiling (Jaime tree)
	"orthoExtract=i" => \$calcOrthoPlacement,
	#ribo profiling (miTag)
	"profileRibosome=i" => \$DoRibofind,
	"riobsomalAssembly=i"  => \$doRiboAssembl,
	"reProfileRibosome=i" => \$RedoRiboFind ,  
	"reRibosomeLCA=i"=> \$RedoRiboAssign,
	"riboMaxRds=i" => \$riboLCAmaxRds,
	"saveRiboRds=i" => \$riboStoreRds,
	"thoroughCheckRiboFinish=i" => \$checkRiboNonEmpty,
	#other tax profilers..
	"profileMetaphlan2=i"=> \$DoMetaPhlan,
	"profileMOTU2=i" => \$DoMOTU2,
	"profileKraken=i"=> \$DoKraken,
	"estGenoSize=i" => \$DoGenoSize, #estimate average size of genomes in data
	"krakenDB=s"=> \$globalKraTaxkDB, #"virusDB";#= "minikraken_2015/";
	#D2s distance
	"calcInterMGdistance=i" => \$DoCalcD2s,
);

setConfigFile($configFile);
  
# die "$DoAssembly\n";
 # ------------------------------------------ options post processing ------------------------------------------
die "No mapping file provided (-map)\b" if ($mapFile eq "");
$map2Assembly=0 if (!$DoAssembly);
$MappingMem .= "G"unless($MappingMem =~ m/G$/);
if ($DoDiamond && $reqDiaDB eq ""){die "Functional profiling was requested (-profileFunct 1), but no DB to map against was defined (-diamondDBs)\n";}
$Assembly_Kmers = "-k $Assembly_Kmers" unless ($Assembly_Kmers =~ m/^-k/);
$sdm_opt{minSeqLength}=$tmpSdmminSL if ($tmpSdmminSL > 0);
$sdm_opt{maxSeqLength}=$tmpSdmmaxSL if ($tmpSdmmaxSL > 0);
$remove_reads_tmpDir = 1 if ($DoFreeGlbTmp || $rmScratchTmp);
$filterFromSource=1 if ($unpackZip );
#$nodeHDDspace .= "G" unless($nodeHDDspace =~ m/G$/);


#dirs from config file--------------------------
$sharedTmpDirP = getProgPaths("globalTmpDir",0) unless ($sharedTmpDirP ne "");
$nodeTmpDirBase = getProgPaths("nodeTmpDir",0) unless ($nodeTmpDirBase ne "");

#programs --------------------------
my $smtBin = getProgPaths("samtools");#"/g/bork5/hildebra/bin/samtools-1.2/samtools";
my $metPhl2Bin = getProgPaths("metPhl2");#"/g/bork3/home/hildebra/bin/metaphlan2/metaphlan2.py";
my $metPhl2Merge = getProgPaths("metPhl2Merge");#"/g/bork3/home/hildebra/bin/metaphlan2/utils/merge_metaphlan_tables.py";
#my $spadesBin = "/g/bork5/hildebra/bin/SPAdes-3.7.0-dev-Linux/bin/spades.py";
my $spadesBin = getProgPaths("spades");#"/g/bork3/home/hildebra/bin/SPAdes-3.7.1-Linux/bin/spades.py";
my $megahitBin = getProgPaths("megahit");
#my $usBin = getProgPaths("usearch");#"/g/bork5/hildebra/bin/usearch/usearch8.0.1421M_i86linux32_fh";
my $bwt2Bin = getProgPaths("bwt2");#"/g/bork5/hildebra/bin/bowtie2-2.2.9/bowtie2";
my $bwaBin = getProgPaths("bwa");#"/g/bork3/home/hildebra/bin/bwa-0.7.12/bwa";
my $d2metaBin = getProgPaths("d2meta");#"/g/bork3/home/hildebra/bin/d2Meta/d2Meta/d2Meta.out";
my $prodigalBin = getProgPaths("prodigal");#"/g/bork5/hildebra/bin/Prodigal-2.6.1/prodigal";
my $augustusBin = getProgPaths("augustus");#"/g/bork3/home/hildebra/bin/augustus-3.2.1/bin/augustus";
my $sambambaBin = getProgPaths("sambamba");#"/g/bork3/home/hildebra/bin/sambamba/sambamba_v0.5.9";
my $npBin = getProgPaths("nonpareil");#"/g/bork5/hildebra/bin/nonpareil/nonpareil";
my $krkBin = getProgPaths("kraken");#"/g/scb/bork/hildebra/DB/kraken/./kraken";
my $diaBin = getProgPaths("diamond");#"/g/bork5/hildebra/bin/diamond/./diamond";
my $nxtrimBin = getProgPaths("nxtrim");#"/g/bork3/home/hildebra/bin/NxTrim/./nxtrim";
my $besstBin = getProgPaths("BESST");#"/g/bork3/home/hildebra/bin/BESST/./runBESST";
#my $novosrtBin = getProgPaths("novosrt");#"/g/bork5/hildebra/bin/novocraft/novosort";
my $GFbin = getProgPaths("gapfiller");#"perl /g/bork5/hildebra/bin/GapFiller/GapFiller_n.pl";
my $flashBin = getProgPaths("flash");
my $pigzBin  = getProgPaths("pigz");
my $sdmBin = getProgPaths("sdm");#"/g/bork3/home/hildebra/dev/C++/sdm/./sdm";
my $rareBin = getProgPaths("rare");#"/g/bork3/home/hildebra/dev/C++/rare/rare";
my $readCov_Bin =getProgPaths("readCov");
my $jgiDepthBin = getProgPaths("jgiDepth");#"/g/bork3/home/hildebra/bin/metabat/./jgi_summarize_bam_contig_depths";
my $bedCovBin = getProgPaths("bedCov");#"/g/bork5/hildebra/bin/bedtools2-2.21.0/bin/genomeCoverageBed";
my $srtMRNA_path = getProgPaths("srtMRNA_path");
my $lambdaIdxBin = getProgPaths("lambdaIdx");
my $trimJar = getProgPaths("trimomatic");
my $fna2faaBin = getProgPaths("fna2faa");

#databases --------------------------
my $himipeSeqAd = getProgPaths("illuminaTS3pe"); #for trimomatic
my $himiseSeqAd = getProgPaths("illuminaTS3se");


#local MATAFILER scripts --------------------------
my $cLSUSSUscript = getProgPaths("cLSUSSU_scr");#"perl /g/bork3/home/hildebra/dev/Perl/16Stools/catchLSUSSU.pl";
my $lotusLCA_cLSU = getProgPaths("lotusLCA_cLSU_scr");#"perl /g/bork3/home/hildebra/dev/Perl/16Stools/lotus_LCA_blast2.pl";
my $krakCnts1 = getProgPaths("krakCnts_scr");#"perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/krak_count_tax.pl";
my $genelengthScript = getProgPaths("genelength_scr");#= "/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/geneLengthFasta.pl";
my $secCogBin = getProgPaths("secCogBin_scr");#"perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/parseBlastFunct.pl";
my $KrisABR = getProgPaths("KrisABR_scr");#"perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/ABRblastFilter.pl";
my $sepCtsScript = getProgPaths("sepCts_scr");#"perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/separateContigs.pl";
my $assStatScr = getProgPaths("assStat_scr");#"perl /g/bork3/home/hildebra/dev/Perl/assemblies/assemblathon_stats.pl";
my $renameCtgScr = getProgPaths("renameCtg_scr");#"perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/renameCtgs.pl";
my $sizFiltScr = getProgPaths("sizFilt_scr");#"perl /g/bork3/home/hildebra/dev/Perl/assemblies/sizeFilterFas.pl";
my $sizSplitScr = getProgPaths("sizSplit_scr");#"perl /g/bork3/home/hildebra/dev/Perl/assemblies/splitFNAbyLength.pl";
my $splitKgdContig = getProgPaths("contigKgdSplit_scr");
my $decoyDBscr = getProgPaths("decoyDB_scr"); #
my $bamHdFilt_scr = getProgPaths("bamHdFilt_scr");

#merge of output tables scripts --------------------------
my $mergeTblScript = getProgPaths("metPhl2Merge");#"/g/bork3/home/hildebra/bin/metaphlan2/utils/merge_metaphlan_tables.py";




#say hello to user 
annoucnce_MATAFILER();


#die $mapFile;

#die $baseOut;
#queing capability
my $JNUM=0;
#my $LocationCheckStrg=""; #command that is put in front of every qsub, to check if drives are connected, sub checkDrives
$submSytem = findQsubSys($submSytem);
my $QSBoptHR = emptyQsubOpt($doSubmit,"",$submSytem);
my %QSBopt = %{$QSBoptHR};
$QSBopt{tmpSpace} = $nodeHDDspace;
my @Spades_Hosts = (); my @General_Hosts = ();
#figure out if only certain node subset has enough HDD space
if (0 && $Spades_HDspace > 100){
	my $locHosts = `bhosts | grep ok | cut -d" " -f 1 | grep compute | tr "\\n" ","`;
	my $tmpStr = `pdsh -w $locHosts -u 4 "df -l" `;
	my $srchTerm = '/$';
	if (`hostname` =~ m/submaster$/){
		$srchTerm = '/tmp';
	}
	#print "psdh done\n";
	#die $tmpStr;
	#54325072 = 52G
	foreach my $l (split(/\n/,$tmpStr)){
		next if ($l !~ m/compute\S+:/);
		next unless ($l =~ m/$srchTerm/);
		#print $l."\n";
		my @hosts = split(/:/,$l);
		my @spl = split(/\s+/,$hosts[1]);
		#die $spl[1]." XX ".$spl[2]." XX ".$spl[3]." XX ".$spl[4]." \n ";
		#print $spl[4] / 1024 / 1024 . "\n";
		if (($spl[4] / 1024 / 1024) > $Spades_HDspace){
			push(@Spades_Hosts,$hosts[0]);
		}
		if (($spl[4] / 1024 / 1024) > 40){
			push(@General_Hosts,$hosts[0]);
		}
	}
	print "Found ".scalar @Spades_Hosts." host machines with > $Spades_HDspace G space\n";
	print "Found ".scalar @General_Hosts." host machines with > 40 G space\n";
	if (scalar @Spades_Hosts ==0 ){die "Not enough hosts for spades temp space found\n";}
	sleep (2);
}




#----------- here are scaffolding external contigs parameters
my $scaffTarExternal = "";my $scaffTarExternalName = ""; my @scaffTarExternalOLib1; my @scaffTarExternalOLib2;
my $scaffTarExtLibTar = ""; my $bwt2ndMapDep = ""; my @bwt2ndMapNmds;

#here the map and some base parameters (base ID, in path, out path) can be (re)set
my %map; my %AsGrps;
my ($hr,$hr2) = readMap($mapFile,0,\%map,\%AsGrps,$oldStylFolders);
%AsGrps = %{$hr2};
%map = %{$hr};
#$baseDir = $map{inDir} if (exists($map{inDir} ));
$baseOut = $map{outDir} if (exists($map{outDir} ));
$baseID = $map{baseID} if (exists($map{baseID} ));

die "provide an outdir in the mapping file\n" if ($baseOut eq "");
die "provide a baseID in the mapping file\n" if ($baseID eq "");

my $runTmpDirGlobal = "$sharedTmpDirP/$baseID/";
my $runTmpDBDirGlobal = "$runTmpDirGlobal/DB/";
system "mkdir -p $runTmpDBDirGlobal" unless (-d $runTmpDBDirGlobal);
#and check that this dir exists...
die "Can't create $runTmpDBDirGlobal\n" unless (-d $runTmpDBDirGlobal);
my $globaldDiaDBdir = $runTmpDBDirGlobal."DiamDB/";
system "mkdir -p $globaldDiaDBdir" unless (-d $globaldDiaDBdir);


#----------- map all reads to a specific reference ---------
#die "@ARGV   $ARGV[0]\n";
if (@ARGV>0 && ($ARGV[0] eq "map2tar" || $ARGV[0] eq "map2DB")){
#in this case primary focus is on mapping and not on assemblies
	if ($ARGV[0] eq "map2DB"){$mapModeCovDo=0;$mapModeDecoyDo=0;$mapModeTogether=0;}
	if ($map2Assembly || $DoAssembly){
		print "Mapping mode: Deactivating mapping and assembly modules\n";
		$map2Assembly=0; $DoAssembly =0;
	}
	my @refDB1 = split(/,/,$refDBall);
	my @bwt2Name1;
	if (defined $bwt2NameAll){
		@bwt2Name1 = split(/,/,$bwt2NameAll) ;
	} elsif ($ARGV[0] eq "map2DB"){
		@bwt2Name1 = ("refDB");
	}
	my @refDB;my @bwt2Name ;
	my %FNrefDB2ndmap;
	for (my $i=0;$i<@refDB1;$i++){
		my @sfiles = glob($refDB1[$i]);
		#die "@sfiles\n$refDB1[$i]\n";
		if (@sfiles>1){
			for (my $j=0;$j<@sfiles;$j++){
				push(@refDB,$sfiles[$j]);
				if ($bwt2Name1[$i] eq "auto"){
					#$sfiles[$j] =~ m/ssemblyfind_list_(.*)\.txt\/(.*)\.contigs_/; my $nmnew = $1.$2; $nmnew =~ s/#/_/g;
					$sfiles[$j] =~ m/\/([^\/]+)\.f.*a$/;
					my $nmnew = $1;
					#die "$nmnew\n";
					push(@bwt2Name,$nmnew);

				} else {
					push(@bwt2Name,$bwt2Name1[$i].$j);
				}
			}
		} elsif (@sfiles == 1) {
			push(@refDB,$sfiles[0]);push(@bwt2Name,$bwt2Name1[$i]);
		} else {
			die "Could not find file for entry $refDB1[$i]\n";
		}
	}
	#die "@refDB\n@bwt2Name\n";
	
	#decoy mapping setup (only required in map2tar
	$make2ndMapDecoy{Lib} = "";
	#die "decoy mapping not ready for multi fastas\n" if (@refDB > 1);
	for (my $i=0;$i<@refDB; $i++){ #take care of ref DB decoy prep
		if ($mapModeDecoyDo || $mapModeTogether){
			my $aref;
			if ($mapModeTogether){
				my $hr = readFasta($refDB[$i]); my %FN = %{$hr};
				%FNrefDB2ndmap = (%FNrefDB2ndmap , %FN);
				$aref = [keys %FN];
			} else {
				$aref = readFastHD($refDB[$i]);
			}
			push(@{$make2ndMapDecoy{regions}}, join(" ",@{$aref}) );
			#die "@{$aref}\n".prefix_find($aref)."\n";
			push(@{$make2ndMapDecoy{region_lcs}},  prefix_find($aref)  );
		}
	}
	my $shrtMapNm = "";
	for ( my $i=0;$i< @bwt2Name; $i++){
		my $substrl = length($bwt2Name[$i]);
		if (@bwt2Name > 3){$substrl = 10;}
		if (@bwt2Name > 5){$substrl = 7;}
		if (@bwt2Name > 7){$substrl = 4;}
		if ($i==0){
			$shrtMapNm .= substr($bwt2Name[$i],0,$substrl);
		} else {
			$shrtMapNm .= ".". substr($bwt2Name[$i],0,$substrl);
		}
		if ($i>7){$shrtMapNm .= ".X".(@bwt2Name - $i)."X"; last;}
	}
	
	#build of combined refDB, if competitive mapping..
	my $bwtDBcore = 10; my $largeDB = 0;
	
	if ($mapModeTogether){
		system "mkdir -p $baseOut/GlbMap/LOGandSUB/" unless (-d "$baseOut/GlbMap/LOGandSUB/");
		system "mkdir -p $runTmpDBDirGlobal/$shrtMapNm" unless (-d "$runTmpDBDirGlobal/$shrtMapNm");
		$map2ndTogRefDB{DB} = "$runTmpDBDirGlobal/$shrtMapNm/$shrtMapNm.fa";
		#die "$map2ndTogRefDB{DB}\n";
		writeFasta(\%FNrefDB2ndmap,"$map2ndTogRefDB{DB}");
		print "$map2ndTogRefDB{DB}\n";
		my ($cmd,$DBbtRef) = buildMapperIdx($map2ndTogRefDB{DB},$bwtDBcore,$largeDB,$MapperProg) ;
		unless (-e "$DBbtRef.bw2.0.sa" || -e  "$DBbtRef.bw2.rev.1.bt2l" ){
			($bwt2ndMapDep,$cmd) = qsubSystem("$baseOut/GlbMap/LOGandSUB/builBwtIdx_comp.sh",$cmd,$bwtDBcore,(int(20/$bwtDBcore)+1) ."G","BWI_compe","","",1,[],\%QSBopt) ;
		}
	}
	
	print "\n=======================\nmap to $refDBall\n=======================\n\n";
	$mapModeActive =1;
	for (my $i=0;$i<@refDB; $i++){
		#$refDB[$i] =~ m/(.*\/)[^\/]+/;
		#my $refDir = $1;
		my $bwt2outDl = "$baseOut/GlbMap/$bwt2Name[$i]/";
		push @bwt2ndMapNmds , $bwt2Name[$i];
		push(@bwt2outD,$bwt2outDl);
		#die $bwt2Name."\n";
		#my $mapFile = "$baseOut/LOGandSUB/inmap.txt";
		if ($rewrite || $rewrite2ndMap){
			print "Deleting previous mapping results..\n";
			$refDB[$i] =~ m/.*\/([^\/]+)$/;
			system("rm -r -f $runTmpDBDirGlobal/$1*");#;mkdir -p $bwt2outDl
		}
		
		$refDB[$i] =~ m/.*\/([^\/]+)$/;
		#print "\n$refDB[$i]\n";
		#die "$bwt2outDl/$1\n";
		system "mkdir -p $bwt2outDl/LOGandSUB" unless (-d "$bwt2outDl/LOGandSUB");
		system "cp $refDB[$i] $bwt2outDl" if ($mapModeCovDo && !-e "$bwt2outDl/$1");
		
		my ($cmd,$DBbtRef) = buildMapperIdx($refDB[$i],$bwtDBcore,$largeDB,$MapperProg) ;
		$DBbtRef =~ s/\.bw2$//;
		$DBbtRef =~ m/.*\/([^\/]+)$/;
		$DBbtRef = "$runTmpDBDirGlobal/$1";#set up to scratch dir to map onto
		$cmd.= "\ncp $refDB[$i]* $runTmpDBDirGlobal\n" unless (-e "$DBbtRef.pak" || ($MapperProg==1 && -e "$DBbtRef"));# if (!$mapModeCovDo && !-e "$bwt2outDl/$1");
		#print $cmd."\n";
		#die $DBbtRef."\n$runTmpDBDirGlobal/\n";
		unless (-e "$DBbtRef.bw2.0.sa" || -e  "$DBbtRef.bw2.rev.1.bt2l" || $mapModeTogether || $mapModeDecoyDo){ #not required for these map mody
			#system $cmd 
			my ($bwt2ndMapDep2,$cmd2) = qsubSystem($bwt2outDl."/LOGandSUB/builBwtIdx$i.sh",$cmd,$bwtDBcore,(int(20/$bwtDBcore)+1) ."G","BWI".$i,"","",1,[],\%QSBopt) ;
			$bwt2ndMapDep .= ";$bwt2ndMapDep2";
		}
		
		#$DBbtRefX = $DBbtRef;
		push(@DBbtRefX,$DBbtRef);
		if($mapModeCovDo){ #get the coverage per gene etc; for this I need a gene prediction
			my $gDir = $bwt2outDl."";
			my $nativeGFF = $refDB[$i];$nativeGFF =~ s/\.[^\.]+$/\.gff/;
			my $gffF = "genes.$bwt2Name[$i].gff";
			#die "$nativeGFF\n";
			if (-e $nativeGFF){
				system "cp $nativeGFF $gDir/$gffF";
			} else {
				system "mkdir -p $gDir";
				$logDir = $gDir;
				my $dEGP = $DO_EUK_GENE_PRED; $DO_EUK_GENE_PRED = 0;
				my $tmpDep1 = run_prodigal_augustus($refDB[$i],$gDir,"",$gDir,"iGP$i","");
				$DO_EUK_GENE_PRED = $dEGP;
				my ($tmpDep,$tmpCmd) = qsubSystem( $bwt2outDl."/LOGandSUB/cpGenes.sh",  "cp $gDir/genes.gff $nativeGFF; mv $gDir/genes.gff $gDir/$gffF",
				1,"1G","genecop".$i,$tmpDep1,"",1,[],\%QSBopt);
				$map2ndDeps .= ";".$tmpDep;
			}
			push(@DBbtRefGFF,$gDir."/$gffF");#"genePred/genes.gff"
			# die "C";
		}
		$logDir="";
		
	}

	#die @bwt2outD."  @bwt2outD\n";
	#die $map2ndDeps;
} elsif (@ARGV > 2 && $ARGV[0] eq "scaffold"){
	$scaffTarExternal = $ARGV[1];
	if (!-f $scaffTarExternal){
		die "Could not find scaffold file:\n$scaffTarExternal\n";
	}
	$scaffTarExternalName = $ARGV[2];
	if (@ARGV>3){
		$scaffTarExtLibTar = $ARGV[3];
	}
} else { #make sure all switches are deactivated
	$mapModeTogether = 0; $mapModeDecoyDo = 0; $mapModeActive = 0;
}

#die "@DBbtRefGFF\n";
#die "@{$make2ndMapDecoy{regions}}\n";

#some base stats kept in vars
my $sequencer = "hiSeq";#plattform the algos have to deal with
#my $DBpath=""; 
my $assDir=""; 
my $continue_JNUM = 0; #debug, set to 0 for full run
my $prevAssembly = ""; my $shortAssembly = "";#files with full length and short length assemblies
my $mmpuOutTab = "";

#fixed dirs for specific set of samples
my $dir_MP2 = $baseOut."pseudoGC/Phylo/MP2/"; #metaphlan 2 dir
my $dir_mOTU2 = $baseOut."pseudoGC/Phylo/mOTU2/"; #mOUT 2 dir
		
my $dir_RibFind = $baseOut."pseudoGC/Phylo/RiboFind/"; #ribofinder dir
my $dir_KrakFind = $baseOut."pseudoGC/Phylo/KrakenTax/$globalKraTaxkDB/"; #kraken dir
system("mkdir -p $baseOut") unless (-d $baseOut);
my $globalLogDir = $baseOut."LOGandSUB/";
system("mkdir -p $globalLogDir/sdm") unless (-d "$globalLogDir/sdm");
open $QSBopt{LOG},">",$globalLogDir."qsub.log";# unless ($doSubmit == 0);
print $globalLogDir."qsub.log\n";
my $collectFinished = $baseOut."runFinished.log\n";
my $globalNPD = $baseOut."NonPareil/";
system "mkdir -p $globalNPD" unless (-d "$globalNPD");
system "cp $mapFile $globalLogDir/inmap.txt";

my $presentAssemblies = 0; my $totalChecked=0;
my @samples = @{$map{smpl_order}}; my @allSmplNames;
my @allFilter1; my @allFilter2; my @inputRawFQs; 
if ($to > @samples){
	print "Reset range of samples to ". @samples."\n";
	$to = @samples;
	#die();
}
my $statStr = ""; my $statStr5 = "";
my %sampleSDMs; 


my $baseSDMopt = getProgPaths("baseSDMopt_rel"); #"/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/data/sdm_opt_inifilter_relaxed.txt";
if ($useSDM ==2 ){$baseSDMopt = getProgPaths("baseSDMopt");}#"/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/data/sdm_opt_inifilter.txt";}
my $baseSDMoptMiSeq = getProgPaths("baseSDMoptMiSeq_rel");#"/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/data/sdm_opt_miSeq.txt";	
if ($useSDM ==2 ){$baseSDMoptMiSeq = getProgPaths("baseSDMoptMiSeq");}#"/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/data/sdm_opt_miSeq_relaxed.txt";	}

my @unzipjobs; my $curUnzipDep = "";
my $sdmjNamesAll = "";
my $waitTime = 0;

my $emptCmd = "sleep 333";
#qsubSystem($globalLogDir."emptyrun.sh","sleep 333",1,"1G",0,"empty","","",1);


#set up kraken human filter
my $krakDeps = ""; my $krakenDBDirGlobal = $runTmpDirGlobal;
if ($DoKraken && $globalKraTaxkDB eq ""){die "Kraken tax specified, but no DB specified\n";}
if ($humanFilter || ($DoKraken) || $DO_EUK_GENE_PRED){
	$krakDeps = prepKraken();
}
my $mOTU2Deps = ""; my $mOTU2Bin = "";
if ($DoMOTU2){
	($mOTU2Deps,$mOTU2Bin) = prepMOTU2();
}

#redo d2s intersample distance?
if ($DoCalcD2s) {$DoCalcD2s = !-e "$baseOut/d2StarComp/d2meta.stone";}





#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------

#--------------------------------------------------------------------------------

#die $to."\n";
for ($JNUM=$from; $JNUM<$to;$JNUM++){
	#die $samples[$JNUM]."\n";
	next if (exists($jmp{$JNUM}));
	#locally used paths for a specific sample
	my $dir2rd=""; my $curDir = "";my $curOutDir = ""; 
	my $curSmpl = $samples[$JNUM];
	$dir2rd = $map{$curSmpl}{dir};
	$dir2rd = $map{$curSmpl}{prefix} if ($dir2rd eq "");
	#print "$curSmpl  $map{$curSmpl}{dir}  $map{$curSmpl}{rddir}  $map{$curSmpl}{wrdir}\n";	next;
	my $SmplName = $map{$curSmpl}{SmplID};
	push (@allSmplNames,$SmplName);
	if ($dir2rd eq "" ){#very specific read dir..
		if ($map{$curSmpl}{SupportReads} ne ""){
			$curDir = "";	$curOutDir = "$baseOut$SmplName/";	
		} else {
			die "Can;t find valid path for $SmplName\n";
		}
		$dir2rd = $SmplName;
	} else {
		$curDir = $map{$curSmpl}{rddir};	$curOutDir = $map{$curSmpl}{wrdir};	
	}

	#die "$curDir\n$curOutDir\n$baseOut\n";
	
	my $samplReadLength = $defaultReadLength; #some default value
	if (exists $map{$curSmpl}{readLength} && $map{$curSmpl}{readLength} != 0){
		$samplReadLength = $map{$curSmpl}{readLength};
	}
	my $curSDMopt = $baseSDMopt;
	#my $iqualOff = 33; #62 for 1st illu

	if (exists($map{$curSmpl}{SeqTech})){
		if ($map{$curSmpl}{SeqTech} eq "GAII_solexa" || $map{$curSmpl}{SeqTech} eq "GAII"){
			#$iqualOff = 59; #really that old??
		} elsif ($map{$curSmpl}{SeqTech} eq "miSeq"){ 
			$curSDMopt = $baseSDMoptMiSeq; 
		}
	} 
	if (!exists($sampleSDMs{$samplReadLength})){
		$sampleSDMs{$samplReadLength} = adaptSDMopt($curSDMopt,$globalLogDir,$samplReadLength);
	}
	my $cAssGrp = $JNUM;
	#print $map{$curSmpl}{AssGroup}."\n";
	if ($map{$curSmpl}{AssGroup} ne "-1"){ $cAssGrp = $map{$curSmpl}{AssGroup};}
	my $cMapGrp = $map{$curSmpl}{MapGroup};
	
	$curSDMopt = $sampleSDMs{$samplReadLength};
	$totalChecked++;
	
	#die $SmplName."  $samplReadLength\n";
	print "\n======= $dir2rd - $JNUM - $SmplName =======\n" unless($silent);
	#my $dir2rd = "alien2-11-0-0";
	my $GlbTmpPath = "$runTmpDirGlobal$dir2rd/"; #curTmpDir
	my $nodeSpTmpD = "$nodeTmpDirBase/$SmplName";
	$logDir = "$curOutDir/LOGandSUB/";
	my @checkLocs = ($GlbTmpPath);
	push(@checkLocs,$curDir)  if ($curDir ne "");
	my $mapOut = "$GlbTmpPath/mapping/";
	#$DBpath="$curOutDir/readDB/";
	my $finalCommAssDir = "$curOutDir/assemblies/metag/";
	my $finalMapDir = "$curOutDir/mapping";
	my $KrakenOD = $curOutDir."Tax/kraken/$globalKraTaxkDB/";
	
	
	#tmp hack to clean single sample mappings <- in the end not used, just stick to old structure..
	#if ($AsGrps{$cMapGrp}{CntAimMap} > 1 ){die "rm -r $finalMapDir $mapOut\n";	next;	}
	
	
	#if (-d "$finalCommAssDir/mismatch_corrector" || -d "$finalCommAssDir/tmp"){
	#	print "Removing temporary Spades Dirs..\n";
	#	system "rm -rf $finalCommAssDir/mismatch_corrector/ $finalCommAssDir/tmp";
	#}
	
	$AsGrps{$cAssGrp}{AssemblSmplDirs} .= $curOutDir."\n";
	my $AssemblyGo=0; my $MappingGo=0; #controls if assemblies / mappings are done in respective groups
	
	#complicated flow control for multi sample assemblies
	$assDir="$runTmpDirGlobal/AssmblGrp_$cAssGrp/";
	die $baseID."\n" if ($cAssGrp eq "");
	$finalCommAssDir = "$baseOut/AssmblGrp_$cAssGrp/metag/" if ( !exists($AsGrps{$cAssGrp}{CntAimAss}) || $AsGrps{$cAssGrp}{CntAimAss}>1);
	#assign job name (dependency) only ONCE
	if ( !exists($AsGrps{$cAssGrp}{CntAss}) || $AsGrps{$cAssGrp}{CntAss} == 0){
		$AsGrps{$cAssGrp}{AssemblJobName} = "_XXASpl$cAssGrp"."XX_" ;
		$AsGrps{$cAssGrp}{CSfinJobName} = "_XXCSpl$cAssGrp"."XX_" ;
	}
	$AsGrps{$cAssGrp}{CntAss} ++;
	print $AsGrps{$cAssGrp}{CntAss} .":".$AsGrps{$cAssGrp}{CntAimAss} unless ($silent);
	if ($AsGrps{$cAssGrp}{CntAss}  >= $AsGrps{$cAssGrp}{CntAimAss} ){
		#print "running assembluy";
		$AssemblyGo = 1;
		if ($AsGrps{$cAssGrp}{CntAimAss}==1){
			$assDir="$GlbTmpPath/assemblies/";
		}
	}
	
	#mapping groups?
	$AsGrps{$cMapGrp}{CntMap} ++;
	print "  ".$AsGrps{$cMapGrp}{CntMap} .":".$AsGrps{$cMapGrp}{CntAimMap}."\n"  unless ($silent);
	if (!exists($AsGrps{$cMapGrp}{CntMap})){ die "Can;t find CntMap for $cMapGrp";}
	if ($AsGrps{$cMapGrp}{CntMap}  >= $AsGrps{$cMapGrp}{CntAimMap} ){
		#print "running mapping";
		$MappingGo = 1;
	}



	if ($DoAssembly ==0 ){$AssemblyGo=0;}
	my $statsDone=0;

	#DELETION SECTION
#redo run - or parts thereof	
	if ($rewrite){
		print "Deleting previous results..\n";
		system ("rm -r -f $assDir $finalCommAssDir");
		system("rm -f -r $curOutDir $GlbTmpPath $collectFinished ");
	} 
	
	my $finAssLoc = "$finalCommAssDir/scaffolds.fasta.filt";
	#die "$finAssLoc\n";
	#automatically delete mapping, if assembly no longer exists..
	my $locRedoAssMapping = $redoAssMapping;
	$locRedoAssMapping =1 if (!-e $finAssLoc && -e "$finalMapDir/$SmplName-smd.bam.coverage.gz");
	
	#delete assembly
	if ($redoAssembly){
		system "rm -fr $finalCommAssDir";
		$locRedoAssMapping=1;
	}
	#delete mapping to assembly
	if ($locRedoAssMapping){
		print "Deleting previous mapping onto assembly\n";
		system "rm -fr $finalMapDir $mapOut";
	}
	system "rm -r $KrakenOD" if ($RedoKraken && -d $KrakenOD);
	if ($RedoRiboFind){system "rm -rf $curOutDir/ribos";}
	if ($RedoRiboAssign){system "rm $curOutDir/ribos//ltsLCA/*.sto";}
	if ($DoRibofind && -e "$curOutDir/LOGandSUB/RiboLCA.sh.etxt"){
		my $LCAetxt = `cat $curOutDir/LOGandSUB/RiboLCA.sh.etxt`;
		if ($LCAetxt =~ m/ParseError thrown: Unexpected character .\@. found/){system "rm -rf $curOutDir/ribos";}

	}

	if ($alwaysDoStats){
		my ($statsHD,$curStats,$statsHD5,$curStats5) = smplStats($curOutDir,$assDir);
		$statsDone=1;
		if ($statStr eq ""){
			$statStr.="SMPLID\tDIR\t".$statsHD."\n".$curSmpl."\t$dir2rd\t".$curStats."\n";
			$statStr5.="SMPLID\tDIR\t".$statsHD5."\n".$curSmpl."\t$dir2rd\t".$curStats5."\n";
		} else {$statStr.=$curSmpl."\t$dir2rd\t".$curStats."\n"; $statStr5.=$curSmpl."\t$dir2rd\t".$curStats5."\n";}
	}

	my $boolGenePredOK=0;
	if ($DO_EUK_GENE_PRED){
		$boolGenePredOK = 1 if (-s "$finalCommAssDir/genePred/proteins.bac.shrtHD.faa" || ($pseudoAssembly && -e "$finalCommAssDir/genePred/proteins.bac.shrtHD.faa"));
	} else {
		$boolGenePredOK = 1 if (-s "$finalCommAssDir/genePred/proteins.shrtHD.faa" || ($pseudoAssembly && -e "$finalCommAssDir/genePred/proteins.shrtHD.faa") );
	}
	#die "$boolGenePredOK\n$finalCommAssDir/genePred/proteins.bac.shrtHD.faa\n";

	my $boolAssemblyOK=0;

	#die $finalCommAssDir;
	#quick fix
	if (!-e "$finalCommAssDir/genePred/genes.per.ctg" && -e "$finalCommAssDir/genePred/genes.gff"){my $tmpGene = "$finalCommAssDir/genePred"; 
		system "cut -f1 $tmpGene/genes.gff | sort | uniq -c | grep -v '#' |  awk -v OFS='\\t' {'print \$2, \$1'} > $tmpGene/genes.per.ctg"} 
	
	#central flag
	$boolAssemblyOK=1 if ($boolGenePredOK && -e "$finAssLoc" && #-e "$finalCommAssDir/genePred/proteins.shrtHD.faa" &&
			(!$map2Assembly || (-e "$finAssLoc.bw2.4.bt2" && -e "$finAssLoc.bw2.3.bt2" && -e "$finalMapDir/$SmplName-smd.bam.coverage.gz") ) );
			#&& (-s "$finalMapDir/$SmplName-smd.bam" || -s "$finalMapDir/$SmplName-smd.cram")
	#die "$boolAssemblyOK $AssemblyGo ass $finalCommAssDir\n";
	#print "$boolAssemblyOK\n$finalCommAssDir/genePred/proteins.shrtHD.faa\n";
	
	my $boolScndMappingOK = 1; my $iix =0;
	my $boolScndCoverageOK = 1;
	if ($rewrite2ndMap){ 
		foreach my $bwt2outDTT (@bwt2outD){
			my $expectedMapCovGZ = "$bwt2outDTT/$bwt2ndMapNmds[$iix]"."_".$SmplName."-0-smd.bam.coverage.gz";
			system "rm -f $expectedMapCovGZ*";
		}
	}
	foreach my $bwt2outDTT (@bwt2outD){
		my $expectedMapCovGZ = "$bwt2outDTT/$bwt2ndMapNmds[$iix]"."_".$SmplName."-0-smd.bam.coverage.gz";
		my $expectedMapBam = "$bwt2outDTT/$bwt2ndMapNmds[$iix]"."_".$SmplName."-0-smd.bam";
		$iix++;
		
		#print $expectedMapCovGZ."\n";
		if ( -e "$expectedMapCovGZ" && -e $expectedMapBam && $MappingGo  ){
			$boolScndMappingOK=1;
		}else{
			$boolScndMappingOK=0; $boolScndCoverageOK=0;
			#be clean
			system "rm -f $expectedMapBam*";
			last;
		}
		if ($mapModeCovDo && (!-e $expectedMapCovGZ.".median.percontig" || !-e $expectedMapCovGZ.".percontig"|| !-e $expectedMapCovGZ.".pergene")){
			$boolScndCoverageOK=0;
			system "rm -f $expectedMapCovGZ.*";

		}

	}
	if (@bwt2outD == 0 ){$boolScndMappingOK = 1 ; $boolScndCoverageOK=1;}#|| !$MappingGo);	
	#print $boolScndMappingOK."\n$boolAssemblyOK\n";
	
	#Kraken flag
	my $calcKraken =0;
	$calcKraken = 1 if ($DoKraken && (!-d $KrakenOD || !-e "$KrakenOD/krakDone.sto"));
	if (!$calcKraken && $DoKraken){
		opendir D, $KrakenOD; my @krkF = grep {/krak\./} readdir(D); closedir D;
		foreach my $kf (@krkF){
			$kf =~ m/krak\.(.*)\.cnt\.tax/; my $thr = $1;# die $thr."  $kf\n";
			system "mkdir -p $dir_KrakFind/$thr" unless (-d "$dir_KrakFind/$thr"); #system "mkdir -p $dir_RibFind/SSU/" unless (-d "$dir_RibFind/SSU/"); system "mkdir -p $dir_RibFind/LSU/" unless (-d "$dir_RibFind/LSU/");
			system "cp $KrakenOD/$kf $dir_KrakFind/$thr/$SmplName.$thr.krak.txt";
		}
	} else {$KrakTaxFailCnts++;}
	
	#system "rm -f $curOutDir/ribos//ltsLCA/LSU_ass.sto $curOutDir/ribos//ltsLCA/Assigned.sto"; fix for new LSU assignments
	my $calcGenoSize=0; $calcGenoSize=1 if ($DoGenoSize && 	!-e "$curOutDir/MicroCens/MC.0.result");
	my $calcRibofind = 0; my $calcRiboAssign = 0;
	$calcRibofind = 1 if ($DoRibofind && (!-e "$curOutDir/ribos//SSU_pull.sto"|| !-e "$curOutDir/ribos//LSU_pull.sto" || ($doRiboAssembl && !-e "$curOutDir/ribos/Ass/allAss.sto" ))); #!-e "$curOutDir/ribos//ITS_pull.sto"|| 
	$calcRiboAssign = 1 if ($DoRibofind && ( #!-e "$curOutDir/ribos//ltsLCA/ITS_ass.sto"||  #ITS no longer required.. unreliable imo
			!-e "$curOutDir/ribos//ltsLCA/Assigned.sto" || !-e "$curOutDir/ribos//ltsLCA/LSU_ass.sto" || !-e "$curOutDir/ribos//ltsLCA/SSU_ass.sto") );
	#if ($calcRiboAssign) {$calcRibofind=1;}
		
	
	#die "$calcRibofind $calcRiboAssign\n";
	if ($calcRibofind || $calcRiboAssign){
		if ($RedoRiboThatFailed ){
			system "rm -r $curOutDir/ribos/";
			$calcRibofind = 1;
			
		}
		$riboFindFailCnts ++ ;
	} elsif ($DoRibofind && !$calcRiboAssign) { #copy files to central dir for postprocessing..
		my @RFtags = ("SSU","LSU");#"ITS",
		foreach my $RFtag (@RFtags){
			system "mkdir -p $dir_RibFind/$RFtag/" unless (-d "$dir_RibFind/$RFtag/"); #system "mkdir -p $dir_RibFind/SSU/" unless (-d "$dir_RibFind/SSU/"); system "mkdir -p $dir_RibFind/LSU/" unless (-d "$dir_RibFind/LSU/");
			my $fromCp = "$curOutDir/ribos/ltsLCA/${RFtag}riboRun_bl.hiera.txt"; my $toCpy = "$dir_RibFind/$RFtag/$SmplName.$RFtag.hiera.txt";
			if ($checkRiboNonEmpty){
				#pretty hard check
				my $numLines=0;
				if (-e "$fromCp.gz"){$numLines = `zcat $fromCp.gz | wc -l`;
				} else {$numLines = `wc -l $fromCp`;} $numLines =~ /(\d+)/; $numLines=$1;
				#die $numLines."\n";
				if ($numLines<=1){$calcRiboAssign=1;$calcRibofind=1;
					system "rm -r $curOutDir/ribos//ltsLCA $curOutDir/ribos/*.sto ";last;
				}
			}
			if (!-e $toCpy  || ( (-e $toCpy  || -e "$toCpy.gz" ) && -e $fromCp && -s $fromCp != -s $toCpy)){
				unlink "$toCpy" if -e ($toCpy);
				if (-e "$fromCp.gz"  ){
					#system "zcat $fromCp.gz > $toCpy" ;
					system "ln -s $fromCp.gz $toCpy.gz" if (!-e "$toCpy.gz");
				} elsif (-e $fromCp) {
					system "gzip $fromCp";
					system "ln -s $fromCp.gz $toCpy.gz" ;
				} else {#just redo..
					system "rm -rf $curOutDir/ribos\n"; 
					$calcRibofind = 1; $calcRiboAssign=1;
					last;
				}
			}
			#system "gzip $fromCp" unless (-e "$fromCp.gz");
			system "rm -f $curOutDir/ribos/ltsLCA/inter${RFtag}riboRun_bl.fna" if (-e "$curOutDir/ribos/ltsLCA/inter${RFtag}riboRun_bl.fna");
		}
	}
	my ($calcDiamond,$calcDiaParse) = IsDiaRunFinished($curOutDir);
	#die "XX $calcDiamond $calcDiaParse\n";
	my $calcMetaPhlan=0;$calcMetaPhlan=1 if ($DoMetaPhlan &&  !-e $dir_MP2."$SmplName.MP2.sto");
	if (!-e $dir_MP2."$SmplName.MP2.sto"){$metaPhl2FailCnts++;}
	my $calcMOTU2=0;$calcMOTU2=1 if ($DoMOTU2 &&  !-e $dir_mOTU2."$SmplName.Motu2.sto");
	if (!-e $dir_mOTU2."$SmplName.Motu2.sto"){$mOTU2FailCnts++;}
	if ($redoCS){
		system("rm -r -f $finalCommAssDir/ContigStats/ $curOutDir/assemblies/metag/ContigStats/ $curOutDir/Binning/");
	}
	if ($map2Assembly && -e "$finalMapDir/$SmplName-smd.bam.coverage.gz" && !-s "$finalMapDir/done.sto"){system "rm -r $finalMapDir";$boolAssemblyOK=0;}

	if ( $boolAssemblyOK ){#causes a lot of overhead but mainly to avoid unpacking reads again..
		print "present: $curOutDir \n"; $presentAssemblies ++;#= $AsGrps{$cAssGrp}{CntAimAss};
		#base is present, but is the additions? 
		my $CRAMsto = "$finalMapDir/$SmplName-smd.cram.sto";

		if ($map2Assembly && $doBam2Cram && !-e $CRAMsto){#.cram.sto to check that everything went well
			$QSBopt{LocationCheckStrg}="";
			bam2cram("$finalMapDir/$SmplName-smd.bam", "$finalCommAssDir/scaffolds.fasta.filt",1,1,$doBam2Cram,$CRAMsto,4);
		}
		
		my $CSfilesComplete = 1;
		$CSfilesComplete = 0 if (!-s "$finalCommAssDir/ContigStats/scaff.pergene.GC3" || !-s "$finalCommAssDir/ContigStats/scaff.4kmer.gz" 
				|| !-s "$curOutDir/assemblies/metag/ContigStats/Coverage.pergene" || !-s "$finalCommAssDir/ContigStats/FMG/FMGids.txt" 
				|| !-s "$curOutDir/assemblies/metag/ContigStats/Coverage.count_pergene" || !-e "$curOutDir/assemblies/metag/assembly.txt");
		#print "$CSfilesComplete CScompl\n";
		#die "$finalCommAssDir/genePred/genes.gff\n$curOutDir/assemblies/metag/ContigStats/Coverage.median.percontig\n".(stat("$finalCommAssDir/genePred/genes.gff"))[9]." > ".(stat("$curOutDir/assemblies/metag/ContigStats/Coverage.median.percontig"))[9]."\n";
		if ($CSfilesComplete && (stat("$finalCommAssDir/genePred/genes.gff"))[9] > (stat("$curOutDir/assemblies/metag/ContigStats/Coverage.median.percontig"))[9]){
			system("rm -r -f  $curOutDir/assemblies/metag/ContigStats ");
		}
		if ($AssemblyGo && !$CSfilesComplete || ($DoBinning && !-s "$finalCommAssDir/Binning/MaxBin/MB.summary") ) {
			print "Running Contig Stats on assembly\n";
			#print "$finalCommAssDir/ContigStats/scaff.pergene.GC\n";
			my $subprts = "agkes"; $subprts .= "m" if ($DoBinning);
			#die "$subprts\n";
			contigStats($curOutDir ,"",$GlbTmpPath,$finalCommAssDir,$subprts,1,1,$samplReadLength);
		} elsif (!$AssemblyGo && (!$CSfilesComplete || ($DoBinning && !-s "$curOutDir/Binning/MaxBin/MB.summary" )
									|| ($DoBinning && !-s "$curOutDir/Binning/MetaBat/MeBa.sto") )){
			print "Running Gene Coverage & Binning\n";
			#die -s "$curOutDir/assemblies/metag/ContigStats/Coverage.pergene" .-s "$curOutDir/Binning/MaxBin/MB.summary" .-s "$curOutDir/Binning/MetaBat/MeBa.sto"."\n"; 
		#my ($jn,$delaySubmCmd2) = contigStats($curOutDir ,$AsGrps{$cAssGrp}{CSfinJobName},$GlbTmpPath,$finalCommAssDir,"a",$AssemblyGo);
			my $subprts = "as"; $subprts .= "m" if ($DoBinning);
			contigStats($curOutDir ,"",$GlbTmpPath,$finalCommAssDir,$subprts,1,1,$samplReadLength);
		} elsif (!$statsDone) {#ready to collect some stats
			my ($statsHD,$curStats,$statsHD5,$curStats5) = smplStats($curOutDir,$assDir);
			$statsDone=1;
			if ($statStr eq ""){
				$statStr.="SMPLID\tDIR\t".$statsHD."\n".$curSmpl."\t$dir2rd\t".$curStats."\n";
				$statStr5.="SMPLID\tDIR\t".$statsHD5."\n".$curSmpl."\t$dir2rd\t".$curStats5."\n";
			} else {$statStr.=$curSmpl."\t$dir2rd\t".$curStats."\n"; $statStr5.=$curSmpl."\t$dir2rd\t".$curStats5."\n";}
		}
		#die "$boolScndMappingOK && !$DoCalcD2s && !$calcRibofind && !$calcDiamond && !$calcMetaPhlan && !$calcKraken\n";
		if ($boolScndCoverageOK && $boolScndMappingOK && !$DoCalcD2s && !$calcRibofind&& !$calcOrthoPlacement && !$calcGenoSize && !$calcDiamond && !$calcDiaParse && !$calcMetaPhlan && !$calcMOTU2 && !$calcKraken && $scaffTarExternal eq ""){
			#free some scratch
			#system "rm -rf $GlbTmpPath &" if ($DoFreeGlbTmp);
			system "rm -rf $GlbTmpPath &" if ($rmScratchTmp );
			print "next";next;
		}
	} elsif ($unfiniRew==1){
		print "Deleting previous results..\n";
		system("rm -f -r $curOutDir $GlbTmpPath $collectFinished");
	} elsif (0&&$doSubmit == 0){
		#system("mkdir -p $GlbTmpPath\nmkdir -p $DBpath\nmkdir -p $assDir\n mkdir -p $logDir");
		next;
	}
#die "X";
	if ($redoFails && ($calcRibofind||$calcDiamond || $calcDiaParse ||$calcMOTU2 || $calcMetaPhlan)){
		die "now recalc $curSmpl\n";
		system ("rm -r -f $assDir $finalCommAssDir");
		system("rm -f -r $curOutDir $GlbTmpPath $collectFinished ");
	}

	#next;
	system("mkdir -p $logDir"); #mkdir -p $GlbTmpPath\n  mkdir -p $DBpath\n mkdir -p $assDir\n
	#435590.58253.NC_009614
	$QSBopt{LocationCheckStrg} = checkDrives(\@checkLocs);
#print $finalCommAssDir."\n";

	#--------------------------------------------------------------
	# get the raw fasta files in Jens metagenomic dirs in ordinary structure
	#unzip and change ifastap & cfp1/cfp2
	if (@unzipjobs > 12){#only run 8 jobs in parallel, lest the cluster breaks down..
		#my @last_n = @unzipjobs[-8..-1]; 
		$curUnzipDep = $unzipjobs[-12];#join(";",@last_n);
		$waitTime=0;
	}
	#set up dirs for this sample
	my $metagAssDir = $assDir."metag/";
	my $geneDir = $metagAssDir."genePred/";
	#system("mkdir -p $metagAssDir $geneDir");
	my $metaGassembly=$metagAssDir."scaffolds.fasta.filt"; 
	my $finalCommScaffDir = "$finalCommAssDir/scaffolds/";
	my $metaGscaffDir = "$metagAssDir/scaffolds/";
	my $finScaffStone = "$finalCommScaffDir/scaffDone.sto";
	my $pseudoAssFile = "$metagAssDir/longReads.fasta.filt";
	my $pseudoAssFileFinal = "$finalCommAssDir/longReads.fasta.filt";
	my $NPD = $curOutDir."nonpareil/";
	#my $finScaffLoc = "";
	my $assemblyDep = "";

#	#-----------------------  FLAGS  ------------------------  
#	#and some more flags for subprocesses
	my $nonPareilFlag = !-s "$NPD/$SmplName.npo" && $DoNP ;
	my $scaffoldFlag = 0; $scaffoldFlag = 1 if (( !-e $finScaffStone) && $map{$curSmpl}{"SupportReads"} =~ /mate/i );
	my $assemblyFlag = 0; $assemblyFlag = 1 if (!-s $finAssLoc && $DoAssembly);
	

	my $assemblyBuildIndexFlag=0; $assemblyBuildIndexFlag=1 if ($DoAssembly && $AssemblyGo && !$assemblyFlag && $map2Assembly 
											&&( !-s "$finAssLoc.bw2.rev.2.bt2" || !-s "$finAssLoc.bw2.4.bt2" || !-s "$finAssLoc.bw2.3.bt2"));
	#print "build $assemblyBuildIndexFlag   $DoAssembly && !$assemblyFlag && $map2Assembly \n";
	my $mapAssFlag = 0; $mapAssFlag = 1 if ($map2Assembly && !-e "$finalMapDir/$SmplName-smd.bam.coverage.gz"  );
	#die "$map2Assembly && !-e $finalMapDir/$SmplName-smd.bam.coverage.gz && $assemblyFlag \n";
	my $pseudAssFlag = 0; $pseudAssFlag = 1 if ($pseudoAssembly && $map{$curSmpl}{ExcludeAssem} eq "0" && (!-e $pseudoAssFileFinal.".sto" || !$boolGenePredOK));
	my $dowstreamAnalysisFlag = 0; 
	#$unpackZip simulates dowstreamAnalysisFlag, just to get sdm running..
	$dowstreamAnalysisFlag=1 if ( $unpackZip || ($calcOrthoPlacement || $scaffTarExternal ne "" || $assemblyFlag  || $pseudAssFlag || $scaffoldFlag  || $nonPareilFlag || $calcGenoSize || $calcDiamond || $DoCalcD2s || $calcKraken || $calcRibofind || $calcMOTU2 || $calcMetaPhlan) );
	my $requireRawReadsFlag = 0;#only list modules that really need raw reads
	$requireRawReadsFlag = 1 if ( !$boolScndMappingOK);
	#die "$dowstreamAnalysisFlag  $assemblyFlag  || $pseudAssFlag || $scaffoldFlag || !$boolScndMappingOK || $nonPareilFlag || $calcDiamond || $DoCalcD2s || $calcKraken || $calcRibofind || $calcMetaPhlan\n";
	
	my $seqCleanFlag = 0; $seqCleanFlag =1 if (!-e "$GlbTmpPath/seqClean/filterDone.stone" && $dowstreamAnalysisFlag );
				;
	#die "$assemblyFlag\t$seqCleanFlag\t$boolScndMappingOK\n";
	my $calcUnzip=0;
	$calcUnzip=1 if ($seqCleanFlag  || $mapAssFlag || !$boolScndMappingOK); #in these cases I need raw reads anyways..
	#die "$calcUnzip = $seqCleanFlag  || $mapAssFlag || !$boolScndMappingOK\n$dowstreamAnalysisFlag\n";
	#die "!$boolScndMappingOK || (!-e $GlbTmpPath/seqClean/filterDone.stone && ( $nonPareilFlag || $calcDiamond || $DoCalcD2s || $calcKraken || $calcRibofind || $calcMetaPhlan)) );\n";

#	#-----------------------  END FLAGS  ------------------------  


	#die "$pseudAssFlag\n$boolGenePredOK\n$pseudoAssFileFinal\n";
	if ($scaffTarExternal ne "" &&  $map{$curSmpl}{"SupportReads"} !~ /mate/i && $scaffTarExtLibTar ne $curSmpl ){print"scNxt\n";next;}
	#has this sample extra reads (e.g. long reads?)
	#die "$assemblyFlag || !$boolScndMappingOK || $nonPareilFlag || $calcDiamond || $DoCalcD2s || $calcKraken\n";
	#die "$curDir\n";
	my $stall4unzip=0;
	if ($stall4unzip &&$doSubmit){
		if (0){ #upsilon
			while(scalar(split(/\n/,`qstat | grep _UZ`)) > 10){print "W4UZ\n";sleep(60);}#set this pretty tame for upsilon
		} elsif (0){
			while(scalar(split(/\n/,`bjobs | grep _UZ`)) > 80){print "W4UZ\n";sleep(60);}
		} else {
			while(scalar(split(/\n/,`squeue -u hildebra | grep _UZ`)) > 120){print "W4UZ\n";sleep(60);}
		}
	}
	my ($jdep,$cfp1ar,$cfp2ar,$cfpsar,$WT,$rawFiles, $mmpuNum, $libInfoRef, $jdepUZ) = 
		seedUnzip2tmp($curDir,$curSmpl,$curUnzipDep,$nodeSpTmpD,
		$GlbTmpPath,$waitTime,$importMocat,$AsGrps{$cMapGrp}{CntMap},$calcUnzip);
	push(@inputRawFQs,$rawFiles);
	if($scaffTarExtLibTar eq $curSmpl){
		@scaffTarExternalOLib1 = @{$cfp1ar}; @scaffTarExternalOLib2 = @{$cfp2ar};
		next unless ($map{$curSmpl}{"SupportReads"} =~ /mate/i );
		#print "@scaffTarExternalOLib1\n";
		#die;
	}
	
	

	$mmpuOutTab .= $dir2rd."\t".$mmpuNum."\n";
	$waitTime = $WT;
	push (@unzipjobs,$jdepUZ) unless ($jdepUZ eq "");
	$AsGrps{$cMapGrp}{SeqUnZDeps} .= $jdep.";";
	$AsGrps{$cAssGrp}{UnzpDeps} .= $jdep.";";
	$AsGrps{$cAssGrp}{readDeps} = $AsGrps{$cAssGrp}{UnzpDeps};
	my @cfp1 = @{$cfp1ar}; my @cfp2 = @{$cfp2ar}; my @libsCFP = ();#stores the read files used plus which library they come from
	if (@cfp1!=@cfp2){print "Fastap path not of equal length:\n@@cfp1\n@@cfp2\n"; die();}
	
	push(@{$AsGrps{$cMapGrp}{RawSeq1}},@cfp1);
	push(@{$AsGrps{$cMapGrp}{RawSeq2}},@cfp2);
	push(@{$AsGrps{$cMapGrp}{RawSeqS}},@{$cfpsar});
	#add info for library used
	my @libInfo = @{$libInfoRef};#local info from unzip step
	push(@libsCFP,@libInfo);
	#idea was to do this check before redoing the unzip step, if filtered already present
	#my $filterReadsPresent = check_sdm_loc($cfp1ar,$cfp2ar,\@libInfo,$GlbTmpPath."seqClean/");

	push(@{$AsGrps{$cMapGrp}{Libs}},@libsCFP);
	open O,">$curOutDir/input_raw.txt"; print O $rawFiles; close O;
	
	#empty links for assembler and nonpareil
	my($arp1,$arp2,$singAr,$matAr,$sdmjN) = ([],[],[],[],"");
	#empty links and objects for merging of reads
	my($mergRdsHr,$mergJbN) = ({},"");
	if (1){ #needs to run to get link to files
		if ($importMocat==1 ){#function actually does nothing
			($arp1,$arp2,$singAr,$sdmjN) = mocat_reorder($cfp1ar,$cfp2ar,$cfpsar,$jdep);
			#my @ta1 = @{$arp1}; my @ta2 = @{$arp2}; die "@{$cfp1ar}XX\n@ta1\n";
			#rewrite ifastp in case sdm takes over from here..
			$cfp1ar = $arp1; $cfp2ar = $arp2;$cfpsar = $singAr;
		} 
		#still punsh the whole thing through sdm..
		if ($useSDM!=0) {
			#$ifastp
			($arp1,$arp2,$singAr,$matAr,$sdmjN) = sdmClean($curOutDir,$cfp1ar,$cfp2ar,$cfpsar,\@libInfo,$nodeSpTmpD."sdm/",$GlbTmpPath."mateCln/",
					,$GlbTmpPath."seqClean/",$curSDMopt,$jdep.";$sdmjN",$dowstreamAnalysisFlag) ;
			
		}
		$sdmjN = krakHSap($arp1,$arp2, $singAr,$nodeSpTmpD,$sdmjN,1) if ($dowstreamAnalysisFlag);
		#die "@{$singAr}";
		($mergRdsHr,$mergJbN) = mergeReads($arp1,$arp2,$sdmjN,$GlbTmpPath."merge_clean/",$doReadMerge,$dowstreamAnalysisFlag);
		#my %mrr = %{$mergRdsHr}; die "$mrr{pair1}\n$mrr{pair2}\n$mrr{mrg}\n";
		#raw files only required for mapping reads to assemblies, so delete o/w
		#die "!$DoAssembly && $importMocat";
		if (!$DoAssembly && $importMocat==0 && $removeInputAgain && !$requireRawReadsFlag){ $sdmjN = cleanInput($cfp1ar,$cfp2ar,$sdmjN,$GlbTmpPath);}
		$AsGrps{$cAssGrp}{readDeps} .= ";$mergJbN";
	}
	#keeps track of all sdm jobs
	$sdmjNamesAll .= ";".$sdmjN;
	push(@allFilter1,@{$arp1});
	push(@allFilter2,@{$arp2});
	#die "@allFilter1\n";
	
	if ($unpackZip){print "next due to onlyFilterZip 1\n";next;}
	
	
	#%%%%%%%%%%%%%%%%   functions only dependent on FILTERED reads   #%%%%%%%%%%%%%%%%
	
	#take long reads and filter for very long reads (454 etc might be long enough)
	#then do gene predictions *instead* of gene predictions on assemblies
	#die $pseudAssFlag."\n";
	if ($pseudAssFlag ){
		my ($psAssDep, $psFile, $metagDir) = createPsAssLongReads($arp1,$arp2,$singAr, $mergJbN.";".$sdmjN, $pseudoAssFile, $finalCommAssDir, $SmplName);#pseudoAssFileFinal
		if ($psAssDep ne ""){
			$AsGrps{$cAssGrp}{pseudoAssmblDep} = $psAssDep;
		}
		#die "$metagDir\n";
		my $prodRun = run_prodigal_augustus($psFile,$metagDir."/genePred/",$psAssDep,$finalCommAssDir,"",$GlbTmpPath);
		if ($prodRun ne ""){
			$AsGrps{$cAssGrp}{pseudoAssmblDep}  = $prodRun;
		#hijack structure originally used by spadesAssmebly routines..
		}
		push(@{$AsGrps{$cAssGrp}{PsAssCopies}}, $assDir."/metag/*",$finalCommAssDir);
		$AsGrps{$cAssGrp}{readDeps} .= ";$prodRun";
	}
	if ($calcOrthoPlacement){
		runOrthoPlacement($arp1,$arp2,$singAr,$mergRdsHr,$curOutDir."orthos/",$nodeSpTmpD."/orthos/",
					$mergJbN.";".$sdmjN);
	}
	if ($calcDiamond || $calcDiaParse){
		my ($djname,$djCln) = runDiamond($arp1,$arp2,$singAr,$mergRdsHr,$curOutDir."diamond/",$globaldDiaDBdir,$nodeSpTmpD."/diaRefDB/",
					$mergJbN.";".$sdmjN,$reqDiaDB); #GlbTmpPath
		$AsGrps{$cAssGrp}{DiamDeps} = $djname.";";
		$AsGrps{global}{DiamDeps} .= ";$djname";
		$AsGrps{global}{DiamCln} = $djCln unless($djCln eq "");
		$AsGrps{$cAssGrp}{readDeps} .= ";$djname";
	}
	
	#non pareil (estimate community size etc)
	if ($nonPareilFlag){
		nopareil($arp1,$NPD, $globalNPD, $SmplName,$sdmjN);
		
		#debug
		next;
	}
	if ($calcGenoSize){#use microbeCensus to get avg genome size
		my $gsJdep = genoSize($arp1,$arp2,$singAr,$mergRdsHr,$curOutDir."MicroCens/",$mergJbN.";".$sdmjN);
		$AsGrps{$cAssGrp}{readDeps} .= ";$gsJdep";
	}
	
	#kraken (estimate taxa abundance
	if ($calcKraken){
		my $krJdep = krakenTaxEst($arp1,$arp2,$singAr,$KrakenOD, $nodeSpTmpD."krak/",$SmplName,$sdmjN);
		$AsGrps{$cAssGrp}{readDeps} .= ";$krJdep";
	}
	if ($calcRibofind || $calcRiboAssign){
		my $ITSrun = detectRibo($arp1,$arp2,$singAr,$nodeSpTmpD."ITS/",$curOutDir."ribos/",$sdmjN,$SmplName,$runTmpDirGlobal); #GlbTmpPath  \@cfp1,\@cfp2
		#$AsGrps{$cAssGrp}{ITSDeps} .= $ITSrun.";";
		$AsGrps{$cAssGrp}{readDeps} .= ";$ITSrun";
	}
	
	#metaphlan2 - taxa abudnance estimates
	if ($calcMetaPhlan){
		my $MP2jname = metphlanMapping($arp1,$arp2,$nodeSpTmpD."MP2/",$dir_MP2,$SmplName,$bwt_Cores,$sdmjN); #\@cfp1,\@cfp2
		$AsGrps{$cAssGrp}{readDeps} .= ";$MP2jname";
	}
	
	#mOTU2  - taxa abundance estimates
	if ($calcMOTU2){
		my $MP2jname = mOTU2Mapping($arp1,$arp2,$singAr,$nodeSpTmpD."Motu2/",$dir_mOTU2,$SmplName,$bwt_Cores,$sdmjN.";".$mOTU2Deps); #\@cfp1,\@cfp2
		$AsGrps{$cAssGrp}{readDeps} .= ";$MP2jname";
	}
	
	
	my $SmplNameX = $SmplName;
	if ($AsGrps{$cAssGrp}{CntAss} > 1){$SmplNameX .= "M".$AsGrps{$cAssGrp}{CntAss};}
	#my @tmp = @{$arp1};die ("ASSflag: ".$assemblyFlag."\n@tmp\n");
	#die "$assemblyFlag\n $AssemblyGo\n";
	if ($assemblyFlag){
		die "Can't do assembly and pseudoassembly on the same sample!\n" if ($pseudAssFlag || $pseudoAssembly);
		#add filtered seq to assembly
		push(@{$AsGrps{$cAssGrp}{FilterSeq1}},@{$arp1});
		push(@{$AsGrps{$cAssGrp}{FilterSeq2}},@{$arp2});
		push(@{$AsGrps{$cAssGrp}{FilterSeqS}},@{$singAr});
		#add jdep to current assembl group
		$AsGrps{$cAssGrp}{SeqClnDeps} .= $sdmjN.";";
		if ($AssemblyGo && $assemblyFlag){
			print "Assembly step";
			#print $AsGrps{$cAssGrp}{AssemblJobName}."\n";		die "@{$AsGrps{$cAssGrp}{FilterSeq1}}"."\n";
			my $hostFilter = 0;
			$hostFilter = 1 if ($AsGrps{$cAssGrp}{CntAimAss} > 3);#reset required HDD space
			my $tmpN ="";
			if ($DoAssembly == 1){
				$tmpN = spadesAssembly( \%AsGrps,$cAssGrp,"$nodeSpTmpD/ass",$metagAssDir,$spadesBayHam ,
					$shortAssembly, $SmplNameX,$hostFilter,$scaffoldFlag) ;
			}elsif($DoAssembly == 2){
				$tmpN = megahitAssembly( \%AsGrps,$cAssGrp,"$nodeSpTmpD/ass",$metagAssDir,$spadesBayHam ,
					$shortAssembly, $SmplNameX,$hostFilter,$scaffoldFlag) ;
			}

			#if mates available, do them here

			postSubmQsub("$logDir/MultiMapper.sh",$AsGrps{$cAssGrp}{PostAssemblCmd},$AsGrps{$cAssGrp}{AssemblJobName},$tmpN);
			$AsGrps{$cAssGrp}{PostAssemblCmd} = "";$AsGrps{$cAssGrp}{AssemblJobName} = $tmpN.";$jdep"; #always add in dep on read extraction
			#die "$AsGrps{$cAssGrp}{AssemblJobName} deps\n";
			push(@{$AsGrps{$cAssGrp}{AssCopies}}, $assDir."/metag/*",$finalCommAssDir);
	
			#call genes, depends on assembly
			if (@{$AsGrps{$cAssGrp}{AssCopies}} == 0){$geneDir = $finalCommAssDir."/genePred/";} #in case assembly already copied over, this needs to be set to copy correctly to finalD
			$AsGrps{$cAssGrp}{prodRun} = run_prodigal_augustus($metaGassembly,$geneDir,$AsGrps{$cAssGrp}{AssemblJobName},$finalCommAssDir,"",$GlbTmpPath);
		}
		#die ("asas $AssemblyGo $assemblyFlag\n");
	} elsif ($AssemblyGo && $AsGrps{$cAssGrp}{PostAssemblCmd} ne ""){#no assembly required, but maybe still other dependent jobs (i.e. mapping)
			print "assembly exists, but postassembly jobs unfinished\n";
			#die "POSTCMD: ".$AsGrps{$cAssGrp}{PostAssemblCmd}."\n";
			postSubmQsub("$logDir/MultiMapper.sh",$AsGrps{$cAssGrp}{PostAssemblCmd},$AsGrps{$cAssGrp}{AssemblJobName},"");
			$AsGrps{$cAssGrp}{PostAssemblCmd} = "";$AsGrps{$cAssGrp}{AssemblJobName} = $jdep; #always add in dep on read extraction
			push(@{$AsGrps{$cAssGrp}{AssCopies}}, $assDir."/metag/*",$finalCommAssDir);
			$metaGassembly = $finAssLoc;
#		die $AsGrps{$cAssGrp}{PostAssemblCmd}."\n";
	} else {
		print "No Assembly routines required\n" if ($DoAssembly!=0);
		$metaGassembly = $finAssLoc;
		$AsGrps{$cAssGrp}{AssemblJobName} = $jdep;
		if (!$boolGenePredOK && $AssemblyGo){
			$geneDir = $finalCommAssDir."/genePred/";
			$AsGrps{$cAssGrp}{prodRun} = run_prodigal_augustus($metaGassembly,$geneDir,$AsGrps{$cAssGrp}{AssemblJobName},$finalCommAssDir,"",$GlbTmpPath);
		}
	}
	
	if ($assemblyBuildIndexFlag){ #in this case asembly was done, but index was never built
		#die "$finAssLoc\n";
		my ($cmdDB,$bwtIdx) = buildMapperIdx($finAssLoc,$Assembly_Cores,0,$MapperProg);#$nCores);
		#die "$cmdDB\n";
		my ($jname,$tmpCmd) = qsubSystem($logDir."mapperIdx.sh",$cmdDB,(int($Assembly_Cores)),int($bwtIdxAssMem/$Assembly_Cores)."G","bwtIdx$JNUM","","",1,[],\%QSBopt) ;
		$AsGrps{$cAssGrp}{AssemblJobName} .= ";$jname";
	}
	
	# 2nd assembly step: scaffolding; maybe move later further down?
	if ($scaffoldFlag){
	#$finalCommScaffDir "$finalCommScaffDir/scaffDone.sto" $finAssLoc $metaGassembly
		my $curAssLoc = $metaGassembly;
		$curAssLoc = $finAssLoc if (-e $finAssLoc);
		#die "@{$AsGrps{$cMapGrp}{RawSeq1}},@{$AsGrps{$cMapGrp}{RawSeq2}},@{$AsGrps{$cMapGrp}{Libs}} scaff\n";
		my ($newScaff,$sdep) = scaffoldCtgs($AsGrps{$cMapGrp}{RawSeq1},$AsGrps{$cMapGrp}{RawSeq2},$AsGrps{$cMapGrp}{Libs},
				[],[],
				$metagAssDir,$nodeSpTmpD,$metaGscaffDir,$AsGrps{$cAssGrp}{AssemblJobName},$bwt_Cores, $SmplNameX,1,"");
		unless ($sdep eq ""){
			$AsGrps{$cAssGrp}{AssemblJobName} = $sdep;
		}
	}
	
	#external contigs to be scaffolded (e.g. TEC2 extracts)
	if ($scaffTarExternal ne ""){
	#die "inscaff\n";
	#die "@scaffTarExternalOLib1\n";
		my $metaGscaffDirExt = "$curOutDir/scaffolds/$scaffTarExternalName/";
		my ($newScaff,$sdep) = scaffoldCtgs($AsGrps{$cMapGrp}{RawSeq1},$AsGrps{$cMapGrp}{RawSeq2},$AsGrps{$cMapGrp}{Libs},
				#\@scaffTarExternalOLib1,\@scaffTarExternalOLib2,
				[],[],
				$scaffTarExternal,$nodeSpTmpD."/SCFEX$scaffTarExternalName/",$metaGscaffDirExt,$sdmjN,$bwt_Cores, $SmplNameX,0,
				$scaffTarExternalName);
	#my($ar1,$ar2,$scaffolds,$GFdir_a) = @_; #.= "_GFI1";
		if (@scaffTarExternalOLib1 > 0 ){
			#die "in gapfill\n$newScaff\n";
			GapFillCtgs(\@scaffTarExternalOLib1,\@scaffTarExternalOLib2,$newScaff,$metaGscaffDirExt."GapFill/",$sdep,$scaffTarExternalName);
		}

		last;
	}
#	die "noscaff";
	
	
	
	#%%%%%%%%%%%%%%%%   functions only dependent on reads   #%%%%%%%%%%%%%%%%
	
	#------------   secondary mapping -----------------
	#print "@bwt2outD && $MappingGo && !$boolScndMappingOK\n";
	if (@bwt2outD>0 && $MappingGo && (!$boolScndMappingOK || !$boolScndCoverageOK) ){#map reads to specific tar
		#collate strings..
		my @mapOutXS;my @bamBaseNameS;
		for (my $i=0;$i<@bwt2outD; $i++){
			$bwt2outD[$i] =~ m/\/([^\/]+)\/*$/;
			my $smplXDB = $1;
			push @mapOutXS, $GlbTmpPath."xtraMaps/$smplXDB/";
			#my $p1ar = $AsGrps{$cAssGrp}{RawSeq1};
			#bwt2Name
			#$AsGrps{$cMapGrp}{CntMap}
			my $fname = $bwt2ndMapNmds[$i]."_".$SmplName."-0";
			#if (length($fname ) > 20){$bwt2ndMapNmds[$i]."_".$SmplName."-0";
			push @bamBaseNameS, $fname;
		}
#		system "rm -rf ".join(" ",@mapOutXS) if ($redo2ndMapping);

		$make2ndMapDecoy{Lib} = $curOutDir if ($mapModeDecoyDo);
		my $cramthebam=0;
		#die "@{$AsGrps{$cMapGrp}{RawSeq1}}\n";
		#map to all refs at once
		my %dirset = 	(nodeTmp=>$nodeSpTmpD,
						outDir => join(",",@bwt2outD),
						glbTmp => $GlbTmpPath."/xtraMaps/",
						glbMapDir => join(",",@mapOutXS));
		#die "XX @DBbtRefX\n";
		my ($map2CtgsX,$delaySubmCmdX,$mapOptHr) = mapReadsToRef(\%dirset,join(",",@bamBaseNameS), 1,
			$AsGrps{$cMapGrp}{RawSeq1},$AsGrps{$cMapGrp}{RawSeq2},$AsGrps{$cMapGrp}{RawSeqS},$bwt_Cores,
			join(",",@DBbtRefX),$AsGrps{$cMapGrp}{SeqUnZDeps}.";".$bwt2ndMapDep, "", 1, $cramthebam,
			$SmplName, $AsGrps{$cMapGrp}{Libs});#$localAssembly);
	# ($dirsHr,$outName, $is2ndMap, $par1,$par2,$Ncore,#hm,m,x,x,x,x,x
	#	$REF,$jDepe, $unaligned,$immediateSubm,#m,x,x,x,m
	#	$doCram,$smpl,$libAR) = @_;#x,x,x
		#------------  and calc coverage for each separate
		#die "X";
		my $sortBamCnt =0;
		
		
		for (my $i=0;$i<@bwt2outD; $i++){
			 my $mapOutX = $mapOutXS[$i]; 
			$dirset{outDir} = $bwt2outD[$i];$dirset{glbMapDir} =$mapOutXS[$i];
			
			my ($map2CtgsY,$delaySubmCmdY,$mapStat)  = bamDepth(\%dirset,					#$mapOutXS[$i],$GlbTmpPath."/xtraMaps/",$nodeSpTmpD,
						$bamBaseNameS[$i],$DBbtRefX[$i],$map2CtgsX,$cramthebam,$mapOptHr);
			#die "$map2CtgsY\n$delaySubmCmdY\n$mapStat\n";
			if ($map2CtgsY ne ""){$sortBamCnt++;}
			#call abundance on newly made genes
			#map2ndDeps being gff file
			if ($mapModeCovDo && !$boolScndCoverageOK){
				if ($mapStat ==2|| $mapStat==0){ #files still on scratch
					$map2CtgsY = calcCoverage("$mapOutX/"."$bamBaseNameS[$i]-smd.bam.coverage.gz",$DBbtRefGFF[$i] ,
						$samplReadLength,$SmplName.".$i",$map2CtgsY.";$map2ndDeps") ;
					push(@{$AsGrps{$cMapGrp}{MapCopiesNoDel}},$mapOutX."/*",$bwt2outD[$i]);
					#print "YY @{$AsGrps{$cMapGrp}{MapCopiesNoDel}}\n";
				} else { #files are already copied
					#die "$bwt2outD[$i]/"."$bamBaseNameS[$i]-smd.bam.coverage.gz\nxx\n";
					my $empty = calcCoverage("$bwt2outD[$i]/"."$bamBaseNameS[$i]-smd.bam.coverage.gz",$DBbtRefGFF[$i] ,
						$samplReadLength,$SmplName.".$i",$map2CtgsY.";$map2ndDeps") ;
				}
				#die "ASD\n";
			} elsif ($mapStat == 2 || $mapStat==0){#check if files need to be copied..
				push(@{$AsGrps{$cMapGrp}{MapCopiesNoDel}},$mapOutX."/*",$bwt2outD[$i]);
			}
			$AsGrps{$cMapGrp}{MapDeps} .= $map2CtgsY.";";
			#my ($jn,$delaySubmCmd2) = contigStats($curOutDir ,$AsGrps{$cAssGrp}{CSfinJobName},$GlbTmpPath,$finalCommAssDir,"a",$AssemblyGo,0);
		}
		print "$sortBamCnt sortings of Bams\n" if ($sortBamCnt > 0);
		#only used for now for the mapping to spec ref
		#die "@{$AsGrps{$cMapGrp}{MapCopiesNoDel}}\n$AsGrps{$cMapGrp}{MapDeps}\n$map2CtgsX\n";
		#print "XX @{$AsGrps{$cMapGrp}{MapCopiesNoDel}}\n";
		my $cln1 = clean_tmp([],[], $AsGrps{$cMapGrp}{MapCopiesNoDel},$AsGrps{$cMapGrp}{MapDeps},"",
			"_mcl"."_$JNUM");
			#die"mcl";
		#print "XX $AsGrps{$cMapGrp}{MapDeps}\n";
		$AsGrps{$cMapGrp}{MapCopiesNoDel} = [];$AsGrps{$cMapGrp}{MapDeps}="";
		$AsGrps{$cAssGrp}{scndMapping} .= $cln1.";";#tmp dir shouldn't be deleted before this is done
		#@cleans = {}; #just deactivate clean up for sec mapping..
	} elsif ($mapModeActive) {
		#still needs delays in cleaning command
		$AsGrps{$cMapGrp}{ClSeqsRm} .= ";".$GlbTmpPath;
		next;
	}
	
	
	
	#print "end of ref map \n";next;
	#die "$map2Assembly && ($DoAssembly || $mapAssFlag)\n";
	#-----------------------   map reads to Assembly      ------------------------------
	#%%%%%%%%%%%%%%%%   functions dependent on assembly -> submit post-assembly   #%%%%%%%%%%%%%%%%
	if ($MappingGo && $map2Assembly && ($DoAssembly || $mapAssFlag)){ #mapping to the assembly (can be multi-sample assembly as well)
		my $cramthebam = 1;
		my %dirset = 	(nodeTmp=>$nodeSpTmpD,
						outDir => "$finalMapDir/",
						glbTmp => $GlbTmpPath."/toMGctgs/",
						glbMapDir => $mapOut);
		my $unAlDir = $mapOut."unaligned/";
		$unAlDir = "" if (!$SaveUnalignedReads);
		my $mapNow =0;
		$mapNow = 1 if ($AssemblyGo ||  -s $finAssLoc);#controls if several samples are assembled together and this needs to be waited for
		#die "$mapNow = ($AssemblyGo ||  -s $finAssLoc)\n";
		#die "@cfp1\n@cfp2\n@{$cfpsar}\n";
	#	print "@libsCFP\n@cfp1\n$cMapGrp\n@{$AsGrps{$cMapGrp}{Libs}} YY\n" if ($JNUM == 14);

		my ($map2Ctgs,$delaySubmCmd,$mapOptHr) = mapReadsToRef(\%dirset,$SmplName,0, 
			$AsGrps{$cMapGrp}{RawSeq1},$AsGrps{$cMapGrp}{RawSeq2},$AsGrps{$cMapGrp}{RawSeqS},$bwt_Cores,
			$metaGassembly,$AsGrps{$cAssGrp}{AssemblJobName},$unAlDir,$mapNow,$cramthebam,
			$SmplName,$AsGrps{$cMapGrp}{Libs});#\@libsCFP);
		my ($map2Ctgs_2,$delaySubmCmd_2,$mapStat)  = bamDepth(\%dirset,    #$mapOutXS[$i],$GlbTmpPath."/xtraMaps/",$nodeSpTmpD,
			$SmplName,$metaGassembly,$map2Ctgs,$cramthebam,$mapOptHr);
			$delaySubmCmd .= "\n".$delaySubmCmd_2;
		#die "$delaySubmCmd $map2Ctgs_2\n";
		if (!${$mapOptHr}{immediateSubm} ){#$map2Ctgs_2 ne ""){
			#store command for later..
			$AsGrps{$cAssGrp}{PostAssemblCmd} .= $delaySubmCmd;
			push(@{$AsGrps{$cAssGrp}{MapCopies}},$mapOut."/*",$finalMapDir);
			$AsGrps{$cAssGrp}{MapDeps} .= $map2Ctgs_2.";";
		}elsif (!-e "$finalMapDir/$SmplName-smd.bam.coverage.gz" && -e "$mapOut/$SmplName-smd.bam.coverage.gz"){ 
			#this part is checking only if files were not copied..
			#push(@{$AsGrps{$cAssGrp}{MapCopies}},$mapOut."/*","$finalMapDir");
			#just do it.. 
			print "Moving mappings from globaltmp to finaldir\n";
			system "mkdir -p $finalMapDir;" unless (-d $finalMapDir);
			system " mv $mapOut/* $finalMapDir";
		}
		#die "$curOutDir/mapping\n" . "$mapOut/$SmplName-smd.bam.coverage.gz"
	#
	}
	
	#doesn't make sense
	# elsif (!-d $finalMapDir && -e "$finalMapDir/$SmplName-smd.bam.coverage.gz"){
	#	#ok, mapping already run, but double check that files were moved
	#	push(@{$AsGrps{$cAssGrp}{MapCopies}},$mapOut."/*","$finalMapDir");
	#} 
	
	
	
	
	
	
	#cleaning of filtered reads & copying of assembly / mapping files
	#$AsGrps{$cAssGrp}{ClSeqsRm} .= $GlbTmpPath."seqClean/".";";
	
	my @copiesNoDels=();@copiesNoDels = @{$AsGrps{$cAssGrp}{PsAssCopies}} if (exists($AsGrps{$cAssGrp}{PsAssCopies}));
	my @cleans = ();
	if ($MappingGo && @bwt2outD==0){ #sync clean of tmp with scnd mapping..
		#push(@cleans , $GlbTmpPath);# $GlbTmpPath,$metagAssDir."seqClean/filter*",
	}
	
	#all dependencies before deleting tmp dirs
	my $totJdeps = $AsGrps{$cAssGrp}{MapDeps} . ";". $AsGrps{$cAssGrp}{scndMapping}.";".$AsGrps{$cAssGrp}{readDeps}.";".$AsGrps{$cAssGrp}{prodRun};
	#die "$totJdeps\n";
	#print $AsGrps{$cAssGrp}{ClSeqsRm}." FF ".$AsGrps{$cMapGrp}{ClSeqsRm}."\n";
	if ($MappingGo && exists($AsGrps{$cAssGrp}{ClSeqsRm})){push(@cleans,split(/;/,$AsGrps{$cAssGrp}{ClSeqsRm} )); $AsGrps{$cMapGrp}{ClSeqsRm} = "";}
	if ($rmScratchTmp ){if (-d $GlbTmpPath || length($totJdeps)>8){push(@cleans,$GlbTmpPath);}
	}
	
	#die "\n@cleans\n";
	
	my @copies = (@{$AsGrps{$cAssGrp}{MapCopies}},@{$AsGrps{$cAssGrp}{AssCopies}});
		

	my $cln1="";
	if (1){
		if (!$remove_reads_tmpDir){@cleans =();}
		$cln1 = clean_tmp(\@cleans,\@copies, \@copiesNoDels,
			$totJdeps,
			$curOutDir,"");#$AsGrps{$cAssGrp}{CSfinJobName}); #.";".$contRun
	}
	$QSBopt{LocationCheckStrg}="";
	
	#clean up assembly groups
	$AsGrps{$cAssGrp}{ClSeqsRm} = ""; @{$AsGrps{$cAssGrp}{MapCopies}} = ();
	$AsGrps{$cAssGrp}{MapDeps} = "";  $AsGrps{$cAssGrp}{readDeps} = ""; $AsGrps{$cAssGrp}{DiamDeps} = "";
	# calc statsitics concercing readqual, mappings, genes & contigs
	
	if ($pseudAssFlag || ($AssemblyGo && $DoAssembly)) {
		my $subprts = "agkse";
		if ($DoBinning){$subprts .= "m";}
		my ($contRun,$tmp33) = contigStats($curOutDir ,$cln1.";".$AsGrps{$cAssGrp}{prodRun},$GlbTmpPath,$finalCommAssDir,$subprts,1,0,$samplReadLength);
		#run contig stats
		postSubmQsub("$logDir/MultiContigStats.sh",$AsGrps{$cAssGrp}{PostClnCmd},$AsGrps{$cAssGrp}{CSfinJobName},$contRun);
		$AsGrps{$cAssGrp}{PostClnCmd} = "";$AsGrps{$cAssGrp}{CSfinJobName} = $contRun;
	
	} else {
		#calculate solely abundance / gene, has to be run after clean & assembly contigstat step
		my ($jn,$delaySubmCmd2) = contigStats($curOutDir ,$cln1.";".$AsGrps{$cAssGrp}{CSfinJobName},$GlbTmpPath,$finalCommAssDir,"a",$AssemblyGo,0,$samplReadLength);
		$AsGrps{$cAssGrp}{PostClnCmd} .= $delaySubmCmd2;
	}
	#debug
	#if ($AssemblyGo){die();}
	#die();

}

print "Main Loop done\n";

#global clean up cmds (like DB removals from scratch)
DiaPostProcess("",$baseOut);

d2metaDist(\@allSmplNames,\@allFilter1,\@allFilter2,$sdmjNamesAll,$baseOut."/d2StarComp/");

close $QSBopt{LOG};

#print input files, sorted by samples
if (@inputRawFQs == @allSmplNames){
	open O,">$baseOut/Input_raw.txt";
	for (my $i=0;$i<@allSmplNames; $i++){
		print O "$allSmplNames[$i]\t$inputRawFQs[$i]\n";
	}
	close O;
}

print "\n$sharedTmpDirP\n".$baseOut."\nFINISHED MATAFILER\n";
if ($statStr ne ""){
	open O,">$baseOut/metagStats.txt";
	print O $statStr;
	close O;
	print "Stats in $baseOut/metagStats.txt\n";
}
if ($statStr5 ne ""){
	open O,">$baseOut/metagStats_500.txt";
	print O $statStr5;
	close O;
	#print "Stats in $baseOut/metagStats_500.txt\n";
}


	#my $dir_MP2 = $baseOut."pseudoGC/Phylo/MP2/"; #metaphlan 2 dir
	#my $dir_RibFind = $baseOut."pseudoGC/Phylo/RiboFind/"; #metaphlan 2 dir
	#my $dir_KrakFind = $baseOut."pseudoGC/Phylo/KrakenTax/"; #metaphlan 2 dir
print "Found ".$presentAssemblies." of ".$totalChecked." samples already assembled\n";
if ($DoRibofind ){ 
	if( $riboFindFailCnts){print "$riboFindFailCnts samples with incomplete RiboFind\n";} 
	else {
		my $mergeMiTagScript = getProgPaths("mrgMiTag_scr");#"/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/miTagTaxTable.pl";
		print "All samples have assigned RiboFinds\n";
		my $mrgCmd = "";
		my @lvls = ("domain","phylum","class","order","family","genus","species","hit2db");
		$mrgCmd .= "$mergeMiTagScript ".join(",",@lvls)." $dir_RibFind/ITS.miTag $dir_RibFind/ITS/*.hiera.txt.gz \n";
		$mrgCmd .= "$mergeMiTagScript ".join(",",@lvls)." $dir_RibFind/SSU.miTag $dir_RibFind/SSU/*.hiera.txt.gz \n";
		$mrgCmd .= "$mergeMiTagScript ".join(",",@lvls)." $dir_RibFind/LSU.miTag $dir_RibFind/LSU/*.hiera.txt.gz \n";
		#die $mrgCmd."\n";
		my $of_exist = 1;
		foreach my $lvl (@lvls){ 
			$of_exist=0 unless (-e "$dir_RibFind/ITS.miTag.$lvl.txt" && -e "$dir_RibFind/LSU.miTag.$lvl.txt" && -e "$dir_RibFind/SSU.miTag.$lvl.txt"); 
			#die "$dir_RibFind/ITS.miTag.$lvl.txt\n$dir_RibFind/LSU.miTag.$lvl.txt\n$dir_RibFind/SSU.miTag.$lvl.txt\n" if (!$of_exist);
		}
		system $mrgCmd."\n" if ($of_exist == 0);
		#system "$mrgCmd";
}}
if ($DoKraken ){if( $KrakTaxFailCnts){print "$KrakTaxFailCnts samples with incomplete KrakenTax\n";} 
	else {print "All samples have assigned Kraken Taxonomy\n";
		opendir D, $dir_KrakFind; my @krkF = grep {/0.*/ && -d $dir_KrakFind.$_} readdir(D); closedir D;
		my $mrgCmd = "";
		foreach my $kf (@krkF){
			#$kf =~ m/krak\.(.*)\.cnt\.tax/; my $thr = $1;# die $thr."  $kf\n";
			$mrgCmd .= "$mergeTblScript $dir_KrakFind/$kf/*.krak.txt > $dir_KrakFind/Krak.$kf.mat\n";
		}
		#die $mrgCmd."\n$dir_KrakFind\n";
		system "$mrgCmd";
}}
if ($DoMetaPhlan){
	if ($metaPhl2FailCnts){print "$metaPhl2FailCnts samples with incomplete Metaphlan assignments\n";}
	else { print "All samples have metaphlan assignments.\n";
		mergeMP2Table($dir_MP2);	
	}
}
if ($DoMOTU2){
	if ($mOTU2FailCnts){print "$mOTU2FailCnts samples with incomplete mOTU2 assignments\n";}
	else { print "All samples have mOTU2 assignments.\n";
		mergeMotu2Table($dir_mOTU2);
	}
}
open O,">$baseOut/MMPU.txt";print O $mmpuOutTab;close O;

exit(0);
die();







































#--------------------------------------------------------------
#get ref genomes
#print("/g/bork5/hildebra/bin/cdbfasta/cdbfasta $PaulRefGenomes");
#if (!-f $thisRefSeq){system("/g/bork5/hildebra/bin/cdbfasta/cdbyank -a $GID $PaulRefGenomes.cidx > $thisRefSeq");}

#--------------------------------------------------------------
#and the assembly
#$cmd = "/g/bork5/hildebra/dev/Perl/assemblies/./multAss.pl $DBpath2 $assDir2 $assDir2/tmp/ $Ref 4 $CutSeq";

#####################################################
#
#####################################################
sub DiaPostProcess(){
	my ($cmd,$baseOut) = @_;
	#also do higher level summaries of diamond to DB mappings
	return if (1 || ! $DoDiamond ); #temporary deactivated
	my $mrgDiScr = getProgPaths("mrgDia_scr");
	$cmd .= "\n\n$mrgDiScr $baseOut\n";
	$cmd .= $AsGrps{global}{DiamCln};
	qsubSystem($globalLogDir."DiaDBcleanup.sh",$cmd ,1,"1G","CDDB",
	$AsGrps{global}{DiamDeps} ,"",1,[],\%QSBopt); #unless ($AsGrps{global}{DiamCln} eq "");

}
sub mergeMotu2Table($){
	my ($inD) = @_;
	print "Merging motu2 files into tax tables..\n";
	opendir(DIR, $inD) or die "Can't find: $inD\n";	
	my @m2f = sort ( grep { /.*\.motu2\.tab\.gz/  && -e "$inD/$_"} readdir(DIR) );	rewinddir DIR;
	#die "@m2f\n";
	my $outD = $inD;
	$outD =~ s/[^\/]+\/?$//;
	my %mat; my %specCnt; my %tax; my @smpls; my %matP; my %taxCnt;
	foreach my $f (@m2f){
		die "no smpl id in file $f\n" unless ($f =~ m /(^.*)\.motu2\.tab\.gz/);
		my $smpl = $1;
		push @smpls,$smpl;
		my ($FH,$OK) = gzipopen("$inD/$f","motu2 file");
		while (my $l = <$FH>){
			next if ($l =~ m/^#/);
			chomp $l;
			my @spl = split /\t/,$l;
			$specCnt{$spl[0]} += $spl[2];
			my $taxo = $spl[1];;
			$mat{$spl[0]}{$smpl} = $spl[2];
			#only needs to be done once
			$taxo =~ s/\|/;/g;
			$taxo =~s/[kpcofgs]__//g;
			$tax{$spl[0]} = $taxo;
			my @lphy = split /;/,$taxo;
			@lphy = ("?","?","?","?","?","?","?") if ($taxo eq "-1");
			my $ntax = "";
			die "@lphy" if (@lphy != 7);
			for (my $lvl =0; $lvl < 7; $lvl ++){
				my $llphy = $lphy[$lvl]; $llphy = "?" if ($llphy eq "");
				$ntax .= ";" if ($lvl >0); $ntax .= $llphy; 
				$matP{$lvl}{$ntax}{$smpl} += $spl[2];
				$taxCnt{$lvl}{$ntax} += $spl[2];
			}
				#die "@lphy";
		}
		close $FH;
	}
#motu matrix
	open O,">$outD/m2.motu.txt";
	foreach my $sm (@smpls){print O "\t$sm";}
	print O "\n";
	foreach my $ta (sort { $specCnt{$b} <=> $specCnt{$a} } keys %specCnt) {
		next if ($specCnt{$ta} <= 0);
		print O $ta;
		foreach my $sm (@smpls){print O "\t".$mat{$ta}{$sm};}
		print O "\n";
	}
	close O;
#higher tax, one mat each
	my @taxLvlN = ("kingdom","phylum","class","order","family","genus","species");
	for (my $lvl =0; $lvl < 7; $lvl ++){
		open O,">$outD/m2.$taxLvlN[$lvl].txt";
		print O $taxLvlN[$lvl];
		foreach my $sm (@smpls){print O "\t$sm";}
		print O "\n";
		foreach my $ta (sort { $taxCnt{$lvl}{$b} <=> $taxCnt{$lvl}{$a} } keys %{$taxCnt{$lvl}}) {
			next if ($taxCnt{$lvl}{$ta} <= 0);
			print O $ta;
			foreach my $sm (@smpls){print O "\t".$matP{$lvl}{$ta}{$sm};}
			print O "\n";
		}
		close O;
	}
	print  "motu2 tax tables are in: $outD\n";
}
sub mergeMP2Table($){
	my ($dir_MP2) = @_;
	my @slvl = ("k__","p__","c__","o__","f__","g__"); my @llvl = ("kingdom","phylum","class","order","family","genus");
	my $mrgCmd = ""; my $redoMP2Tables = 0;
	my $premrgCmd = "$mergeTblScript $dir_MP2/*MP2.txt > $dir_MP2/tmp.All.MP2.mat\n" ;
	for (my $i=0;$i<@slvl;$i++){
		my $outF = "$dir_MP2/MP2.all.$llvl[$i].mat";
		if (!-e "$outF" || $redoMP2Tables){
			unless ($premrgCmd eq ""){$mrgCmd.=$premrgCmd;$premrgCmd="";	}
			$mrgCmd .= "head -n1  $dir_MP2/tmp.All.MP2.mat > $outF\n";
			$mrgCmd .= "cat  $dir_MP2/tmp.All.MP2.mat | grep \"".$slvl[$i]."[^\\|]*\\s\" | sed 's/|/;/g' >> $outF\n" ;
		}
	}
	#die "$mrgCmd\n";

	$premrgCmd = "$mergeTblScript $dir_MP2/*MP2.noV.noB.txt > $dir_MP2/All.MP2.noV.noB.mat\n";
	for (my $i=0;$i<@slvl;$i++){
		my $outF = "$dir_MP2/MP2.noV.noB.$llvl[$i].mat";
		if (!-e "$outF" || $redoMP2Tables){
			unless ($premrgCmd eq ""){$mrgCmd.=$premrgCmd;$premrgCmd="";	}
			$mrgCmd .= "head -n1  $dir_MP2/tmp.All.MP2.mat > $outF\n";
			$mrgCmd .= "cat $dir_MP2/All.MP2.noV.noB.mat | grep \"".$slvl[$i]."[^\\|]*\\s\" | sed 's/|/;/g' >> $outF\n"  unless (-e "$outF"&& !$redoMP2Tables);
		}
	}
	$mrgCmd .= "rm -f $dir_MP2/All.MP2.noV.noB.mat\n\n";
	$premrgCmd = "$mergeTblScript $dir_MP2/*MP2.noV.txt > $dir_MP2/All.MP2.noV.mat\n";
	for (my $i=0;$i<@slvl;$i++){
		my $outF = "$dir_MP2/MP2.noV.$llvl[$i].mat";
		if (!-e "$outF" || $redoMP2Tables){
			unless ($premrgCmd eq ""){$mrgCmd.=$premrgCmd;$premrgCmd="";	}
			$mrgCmd .= "head -n1  $dir_MP2/tmp.All.MP2.mat > $outF\n";
			$mrgCmd .= "cat $dir_MP2/All.MP2.noV.mat | grep \"".$slvl[$i]."[^\\|]*\\s\" | sed 's/|/;/g'  >> $outF\n"  unless (-e "$outF"&& !$redoMP2Tables);
		}
	}
	$mrgCmd .= "rm -f $dir_MP2/All.MP2.noV.mat\n\n";
	#viruses
	$premrgCmd = "$mergeTblScript $dir_MP2/*MP2.VirusOnly.txt > $dir_MP2/All.MP2.VirusOnly.mat\n";
	for (my $i=0;$i<@slvl;$i++){
		my $outF = "$dir_MP2/MP2.VirusOnly.$llvl[$i].mat";
		if (!-e "$outF" || $redoMP2Tables){
			unless ($premrgCmd eq ""){$mrgCmd.=$premrgCmd;$premrgCmd="";	}
			$mrgCmd .= "head -n1  $dir_MP2/tmp.All.MP2.mat > $outF\n";
			$mrgCmd .= "cat $dir_MP2/All.MP2.VirusOnly.mat | grep \"".$slvl[$i]."[^\\|]*\\s\" | sed 's/|/;/g'  >> $outF\n"  unless (-e "$outF"&& !$redoMP2Tables);
		}
	}
	$mrgCmd .= "rm -f $dir_MP2/tmp.All.MP2.mat $dir_MP2/All.MP2.VirusOnly.mat\n\n";
	

	system "$mrgCmd";
	#die $mrgCmd."\n";
}

#calculates the hmm based freq estimates and divergence from these -> used for dist matrix
sub d2metaDist{
	my ($arSmpls,$arPaths1,$arPaths2,$deps,$outPath) = @_;
	
	my @paths = @{$arPaths1}; my @Smpls = @{$arSmpls};
	if(!$DoCalcD2s){return;}
	if (@paths < 1){print "Not enough samples for d2s!\n";return;}
	print "Calculating kmer distances for ".@paths." samples\n";
	system "mkdir -p $outPath/LOGandSUB";
	my $d2MK = 6;
	my $smplFile = "$outPath/mapd2s.txt";
	open O,">$smplFile";
	for (my $i=0;$i<@paths;$i++){
		print O "$paths[$i] $Smpls[$i]\n";
	}
	close O;
	my $cmd = "";
	$cmd .= "cd $outPath\n";
	$cmd .= "$d2metaBin $d2MK $smplFile Q\n"; #or Q for fastQ
	$cmd .= "touch $outPath/d2meta.stone\n";
	my $jobN = ""; my $tmpCmd;
	unless (-e "$outPath/d2meta.stone"){
		$jobN = "_d2met";
		($jobN, $tmpCmd) = qsubSystem($outPath."/LOGandSUB/d2Met.sh",$cmd,1,"80G",$jobN,"$deps","",1,\@General_Hosts,\%QSBopt) ;
	}
	return $jobN;
}


sub postSubmQsub(){#("$logDir/MultiMapper.sh",$AsGrps{$cAssGrp}{PostAssemblCmd},$AsGrps{$cAssGrp}{AssemblJobName},$SmplName);
	my ($outf,$cmdM,$placeh,$jobN) = @_;
	return if ($cmdM eq "");
	print "Replacing Job $placeh with $jobN\n";
	$cmdM =~ s/$placeh/$jobN/g;
	$cmdM =~ s/ -w "done\(\)"//g;
	#die $AsGrps{$cAssGrp}{PostAssemblCmd}."\n";
	open O,">$outf"; print O $cmdM; close O;
	print "$outf\n";
	system "bash $outf";
}

sub detectRibo(){
	my ($ar1,$ar2,$sar,$tmpP,$outP,$jobd,$SMPN,$glbTmpDDB) = @_;
	my $numCore = 12;
	my $numCore2 = 24;

	
	my @re1 = @{$ar1}; my @re2 = @{$ar2}; my @singl = @{$sar};
	#print "ri"; 
	if (@re1 > 1 || @re2 > 1){
		#print"\nWARNING::\nOnly the first read file will be searched for ribosomes\n";
		#first create new tmp file
	}
	
	#copy DB to server
	my $DBrna = "$glbTmpDDB/rnaDB/";
	my $DBrna2 = "$glbTmpDDB/LCADB/";
	if ($globalRiboDependence{DBcp} eq "" ){

		my $DBcmd = "";
		my $DBcores = 1;
		$globalRiboDependence{DBcp}="alreadyCopied";
		#my $ITSfilePref = $1;
		my @DBs = split(/,/,getProgPaths("srtMRNA_DBs"));
		my @DBsIdx = @DBs;my @DBsTestIdx = @DBs; my $filesCopied = 1;
		#die @DBs."@DBs\n";
		if ( !-d $DBrna ){
			$DBcmd .= "mkdir -p $DBrna\n";
		}
		for (my $ii=0;$ii<@DBsIdx;$ii++){
			$DBsIdx[$ii] =~ s/\.fasta$/\.idx/;
			$DBsTestIdx[$ii] =~ s/\.fasta$/\.idx\.kmer_0\.dat/;
			if ( -e "$DBrna//$DBs[$ii]"  && -e "$DBrna//$DBsTestIdx[$ii]"  ){
				next;
			}
			die "\nCould not find expected sortmerna file:\n$srtMRNA_path/rRNA_databases/$DBs[$ii]\n" if ( !-e "$srtMRNA_path/rRNA_databases/$DBs[$ii]"  );
			if ( !-e "$srtMRNA_path/rRNA_databases/$DBsTestIdx[$ii]"  ){
				$DBcmd .= "$srtMRNA_path./indexdb_rna --ref $srtMRNA_path/rRNA_databases/$DBs[$ii],$srtMRNA_path/rRNA_databases/$DBsIdx[$ii]\n";
			}
			$DBcmd .= "cp $srtMRNA_path/rRNA_databases/$DBs[$ii] $srtMRNA_path/rRNA_databases/$DBsIdx[$ii]* $DBrna\n";
		}
		#die @DBs."@DBs\n";
		my $ITSDBfa = getProgPaths("ITSdbFA",0);
		if ($ITSDBfa ne ""){ #only do if not empty.. otherwise ignore (not required)
			my $ITSDBpref = $ITSDBfa;$ITSDBpref =~ s/\.fa.*$//;
			my $ITSDBidx = $ITSDBfa; $ITSDBidx =~ s/\.fa.*$/\.idx/;
			$ITSDBpref =~ m/\/([^\/]+)$/;
			$ITSDBpref=~ m/(^.*)\/[^\/]+/;
			
			if (!-e "$ITSDBpref.idx.kmer_0.dat"){ #ITS DBs
				#die "$ITSDBpref\n$$ITSDBpref.idx.kmer_0.dat\n";
				#$DBcmd .= "cp /g/bork3/home/hildebra/DB/MarkerG/ITS_fungi/sh_general_release_30.12.2014.* $DBrna\n";
				if (!-e "$ITSDBfa"){
					print "Missing $ITSDBfa  ITS DB file!\n"; exit(32);
				}
				if (!-e "$ITSDBidx.kmer_0.dat"){
					$DBcmd .= "$srtMRNA_path./indexdb_rna --ref $ITSDBfa,$ITSDBidx\n";
				}
				$DBcmd .= "cp ${ITSDBpref}* $DBrna\n";
				#has to be noted that this doesn't need to happen again
				#print "ribo DB already present\n";
				
				#$DBcmd = "";
			} 
		}
		#and get flash DBs as well over to that dir
		my @DBn = ("LSUdbFA","LSUtax","SSUdbFA","SSUtax","ITSdbFA","ITStax","PR2dbFA","PR2tax");
		my $LCAar = getProgPaths(\@DBn,0);
		my @LCAdbs = @{$LCAar}; 
		#die "@LCAdbs\n".@LCAdbs."\n";
#			("/g/bork3/home/hildebra/DB/MarkerG/SILVA/123/SLV_123_LSU_sorted_097_centroids.fasta*","/g/bork3/home/hildebra/dev/lotus//DB//SLV_123_LSU.tax",
#			"/g/bork3/home/hildebra/DB/MarkerG/SILVA/123//SLV_123_SSU_sorted_0.97_centroids*", "/g/bork3/home/hildebra/dev/lotus//DB//SLV_123_SSU.tax",
#			"/g/bork3/home/hildebra/DB/MarkerG/SILVA/128/SLV_128_LSU.fa*","/g/bork3/home/hildebra/dev/lotus//DB//SLV_128_LSU.tax",
#			"/g/bork3/home/hildebra/DB/MarkerG/SILVA/128//SLV_128_SSU.fa*", "/g/bork3/home/hildebra/dev/lotus//DB//SLV_128_SSU.tax",
#			"/g/bork3/home/hildebra/DB/MarkerG/ITS_combi/ITS_comb.fa*","/g/bork3/home/hildebra/DB/MarkerG/ITS_combi/ITS_comb.tax",
			#"/g/bork3/home/hildebra/dev/lotus//DB//UNITE/sh_refs_qiime_ver7_99_02.03.2015.fasta", "/g/bork3/home/hildebra/dev/lotus//DB//UNITE/sh_taxonomy_qiime_ver7_99_02.03.2015.txt",
#			"/g/bork3/home/hildebra/DB/MarkerG/PR2/gb203_pr2_all_10_28_99p.fasta*", "/g/bork3/home/hildebra/DB/MarkerG/PR2/PR2_taxonomy.txt");
		#check first if the lambda DB was already built
		for (my $kk=0;$kk<@LCAdbs; $kk+=2){
			my $DB = $LCAdbs[$kk];
			#print "$DB\n";
			unless (-e $DB){print "$DBn[$kk] not found, won't use it\n";next;}
			die "wrong DB checked for index built:$DB\n" if ($DB =~ m/\.tax$/);
#			if (!-f $DB.".dna5.fm.sa.val"  ) { #old lambda 1.0x style
			if (!-f $DB.".lambda/index.lf.drp"  ) { #new 1.9x style
				print "Building LAMBDA index anew (may take up to an hour)..\n";
				$DBcores = 12;
				$DBcmd .= "$lambdaIdxBin -p blastn -t $DBcores -d $DB\n";
				#die "$DBcmd\n";
			}
		}
		$LCAdbs[2] =~ m/\/([^\/]+)$/;
		my $SLVtestNme = $1;
		#die "$SLVlsuNme\n";
		#print "$DBrna2/SLV_128_LSU.tax || !-e $DBrna2/gb203_pr2_all_10_28_99p.fasta  $DBrna2/ITS_comb.fa.dna5.fm.sa.val\n";
		if (!-d $DBrna2 || !-e $DBrna2."/$SLVtestNme.lambda/index.lf.drp"|| !-e $DBrna2."/$SLVtestNme" ){
			$DBcmd .= "mkdir -p $DBrna2\n" if (!-d $DBrna2);
			my $jstr = join("* ",@LCAdbs);
			$jstr =~ s/\s\*//g;
			$jstr =~ s/^\*//g;
			#die "$jstr\n";
			$DBcmd.= "cp -r ". $jstr . " $DBrna2";
			#die "$DBcmd\n";
		}
		my $jN = "_RRDB$JNUM"; my $tmpCmd;
		#die $DBcmd."$DBrna/ITS_comb.idx.kmer_0.dat";
		if ($DBcmd ne ""){
			#die $DBcmd."\n";
			($jN, $tmpCmd) = qsubSystem($logDir."RiboDBprep.sh",$DBcmd,$DBcores,"10G",$jN,"","",1,\@General_Hosts,\%QSBopt);
			$globalRiboDependence{DBcp} = $jN;
		}
	}
	#die;
	
	#first detect LSU/SSU/ITS in metag
	my $tmpDY = "$tmpP/SMRNA/";
	my $cmd = "\n\n";
	#die "$readsRpairs\n";
	my $readConfig = 1;
	my $numCoreL = int($numCore / 2);
	if (@re1 > 0){
		$cmd .= "$cLSUSSUscript '".join(";",@re1)."' '". join(";",@re2)."' ";
		if (@singl>0){
			$cmd .= "'".join(";",@singl) . "' $tmpDY $outP $numCore $SMPN $doRiboAssembl $DBrna\n\n"; #tmpP < scratch too slow
		} else {
			$cmd .="'-1' $tmpDY $outP $numCore $SMPN $doRiboAssembl $DBrna\n\n"; #tmpP < scratch too slow
		}
	} else {
		$readConfig = 0;
		$cmd .= "$cLSUSSUscript '-1' '-1' '".join(";",@singl)."' $tmpDY $outP $numCore $SMPN $doRiboAssembl $DBrna\n\n"; #tmpP < scratch too slow
	}
	#this part assigns tax
	my $tmpDX = "$tmpP/LCA/";
	my $numCoreL2 = int($numCore2) ;
	#my $readConfig =$readsRpairs;
	$readConfig=2 if (@singl>0 && $readConfig);
	#ver 2
	#my $cmd2 = "$lotusLCA_cLSU $outP $SMPN $numCoreL2 $DBrna2 $tmpDX $readConfig\n\n";
	#ver 3
	my $cfgstr = "";
	$cfgstr = "-config $configFile " if ($configFile ne "" );
	my $cmd2 = "$lotusLCA_cLSU -dir $outP -smplID $SMPN -cores $numCoreL2 -DBdir $DBrna2 -tmpD $tmpDX -keepReads $riboStoreRds -pairedRds $readConfig $cfgstr -maxReadNum $riboLCAmaxRds\n\n";
	
	
	#die $cmd2."\n";
	my $jobName="";
	my $Scmd = "";
	#die $doRiboAssembl."\n".$cmd."\n";
	#die "$outP/reads_LSU.log\n";
	my $allLCAstones = 0; 
	$allLCAstones = 1 if ( -e "$outP//ltsLCA/LSU_ass.sto" && -e "$outP//ltsLCA/SSU_ass.sto" );#&& -e "$outP//ltsLCA/ITS_ass.sto");

	if (-d $outP  && -e "$outP/SSU_pull.sto" && -e "$outP/LSU_pull.sto" &&  #&& -e "$outP/ITS_pull.sto"
		-s "$outP//ltsLCA/LSUriboRun_bl.hiera.txt" && $allLCAstones &&
		($doRiboAssembl && -e $outP."/Ass/allAss.sto" ) ){
		#really everything done
		$jobName = $jobd;
	} else {
		$jobd.=";".$globalRiboDependence{DBcp} unless ($globalRiboDependence{DBcp} eq "alreadyCopied");
		my $tmpCmd; my $mem = "3G";
		#better to double check calcRiboFind
		my $calcRiboFind=0;$calcRiboFind = 1 if( !-e "$outP/SSU_pull.sto"|| !-e "$outP/LSU_pull.sto" || ($doRiboAssembl && !-e $outP."/Ass/allAss.sto"));
		if (  $calcRiboFind ){ #!-e "$outP/ITS_pull.sto"||
			$jobName = "_RF$JNUM"; 
			#$mem = "5G" if ($doRiboAssembl);
			($jobName, $tmpCmd) = qsubSystem($logDir."RiboFinder.sh",$cmd,$numCore,$mem,$jobName,$jobd,"",1,[],\%QSBopt);
		} else {
			$jobName = $jobd;
		}
		if (!-e "$outP//ltsLCA/LSUriboRun_bl.hiera.txt" || !-e "$outP//ltsLCA/SSUriboRun_bl.hiera.txt" || !$allLCAstones ){ #|| !-e "$outP//ltsLCA/ITSriboRun_bl.hiera.txt" 
			$jobd=$jobName; $mem="4G";
			$jobd .= ";".$globalRiboDependence{DBcp} unless ($globalRiboDependence{DBcp} eq "alreadyCopied");
			$QSBopt{useLongQueue} = 0;
			($jobName, $tmpCmd) = qsubSystem($logDir."RiboLCA.sh",$cmd2,$numCore2,$mem,"_RA$JNUM",$jobName,"",1,[],\%QSBopt);
			$QSBopt{useLongQueue} = 0;
		}
	}
	return $jobName;
}
sub IsDiaRunFinished($){
	my ($curOutDir) = @_;
	my @alldbs = split /,/,$reqDiaDB;
	if (!$DoDiamond){return (0,0);}
	if ($rewriteDiamond && @alldbs == $maxReqDiaDB){ system "rm -r $curOutDir/diamond/" if (-d "$curOutDir/diamond/");}
	my $cD = 1; my $pD = 0;
	if ($rewriteDiamond){$redoDiamondParse = 1;}
	if ($redoDiamondParse && @alldbs == $maxReqDiaDB){
		system "rm -r $curOutDir/diamond/CNT*";
	}
	foreach my $term (@alldbs){
		#print $term."   $cD, $pD\n";
		if ($redoDiamondParse ){#&& ( -e "$curOutDir/diamond/dia.$term.blast.gz.stone" || -e "$curOutDir/diamond/dia.$term.blast.srt.gz.stone") ){ 
			system "rm -f $curOutDir/diamond/dia.$term.blast.*.stone" ;
			system "$secCogBin -i $curOutDir/diamond/XX -DB $term -eval $diaEVal -mode 4";
			system "rm -fr $curOutDir/diamond/ABR/" if ($term eq "ABR");
		}
		if ($rewriteDiamond ){system "rm -f $curOutDir/diamond/dia.$term.blast*" ;$pD=1; $cD=1;}
		#die "$rewriteDiamond\n";
#print "$curOutDir/diamond/dia.$term.blast.gz\n";
		#die "$curOutDir/diamond/dia.$term.blast.gz\n$curOutDir/diamond/dia.$term.blast.srt.gz";
		if ((-e "$curOutDir/diamond/dia.$term.blast.gz" || -e "$curOutDir/diamond/dia.$term.blast.srt.gz")){$cD = 0; }#system "rm $curOutDir/diamond/dia.$term.blas*.gz";}
		$pD = 1 if (!-e "$curOutDir/diamond/dia.$term.blast.srt.gz.stone");#  <- last version always requires .srt.gz
	}
	#die "$cD, $pD\n";
	$cD = 0 if ($pD==0);
	return ($cD,$pD);
}

sub prepDiamondDB($ $ $){#takes care of copying the respective DB over to scratch
	my ($curDB,$CLrefDBD,$ncore) = @_;
	my ($DBpath ,$refDB ,$shrtDB) = getSpecificDBpaths($curDB,0);
	system "mkdir -p $CLrefDBD" unless (-d $CLrefDBD);
	my $clnCmd = "";
	if ($globalDiamondDependence{$curDB} eq "" ){
		my $DBcmd = ""; 
		# check for pr.db.dmnd
		my $ncoreDB=1;
		my $epoTS = 0; my $refDBnew=0;
		$epoTS = ( stat "$DBpath$refDB.db.dmnd" )[9] if (-e "$DBpath$refDB.db.dmnd");
		my $epoTSdia = ( stat "$diaBin" )[9];
		#$timestamp = POSIX::strftime( "%d%m%y", localtime( $epoTS));
		#die "time: $epoTSdia $epoTS \n";
		if ($epoTS < $epoTSdia){
			$ncoreDB = $ncore;$refDBnew=1; 
			system "rm -f $DBpath$refDB.db*";
			$DBcmd .= "$diaBin makedb --in $DBpath$refDB -d $DBpath$refDB.db -p $ncoreDB\n";
		}
		unless (-e "$DBpath$refDB.length"){
			$DBcmd .= "$genelengthScript $DBpath$refDB $DBpath$refDB.length\n";
		}
		#$clnCmd .= "rm -rf $CLrefDBD;" if (length($CLrefDBD)>6);
		#idea here is to copy to central hdd (like /scratch)
		system "rm -f $CLrefDBD/$refDB.db.dmnd"  if (($refDBnew || $rewriteDiamond )&& -d $CLrefDBD);
		#print " !-e $CLrefDBD/$refDB.db.dmnd && !-e $CLrefDBD/$refDB.length\n ";
		if ( -e "$CLrefDBD/$refDB.db.dmnd" && -e "$CLrefDBD/$refDB.length" 
			#&& ($curDB eq "NOG" && !-e "$CLrefDBD/NOG.members.tsv") &&
			#(($curDB ne "KGB" && $curDB ne "KGM" && $curDB ne "KGE")|| -s "$CLrefDBD/genes_ko.list")
			){
			#has to be noted that this doesn't need to happen again
			$globalDiamondDependence{$curDB}="$shrtDB-1";
		} else {
			$DBcmd .= "mkdir -p $CLrefDBD\n";
			$DBcmd .= "cp $DBpath$refDB.db.dmnd $DBpath$refDB.length $CLrefDBD\n";
		}
		if ($curDB eq "NOG" && !-s "$CLrefDBD/NOG.members.tsv" && !-s "$CLrefDBD/NOG.annotations.tsv"){
			system "rm -f $CLrefDBD/NOG* $CLrefDBD/all_species_data.txt";
			$DBcmd .= "cp $DBpath/all_species_data.txt $DBpath/NOG.members.tsv $DBpath/NOG.annotations.tsv $CLrefDBD\n";
		}
		if ($curDB eq "CZy" && !-s "$CLrefDBD/MohCzy.tax"){
			system "rm -f $CLrefDBD/MohCzy.tax $CLrefDBD/cazy_substrate_info.txt";
			$DBcmd .= "cp $DBpath/MohCzy.tax $DBpath/cazy_substrate_info.txt $CLrefDBD\n";
		}
		if (($curDB eq "KGB" || $curDB eq "KGM" || $curDB eq "KGE") && !-s "$CLrefDBD/genes_ko.list"){
			system "rm -f $CLrefDBD/genes_ko.list $CLrefDBD/kegg.tax.list";
			$DBcmd .= "cp $DBpath/genes_ko.list $DBpath/kegg.tax.list $CLrefDBD\n";
		}
		if ($curDB eq "ABRc" && !-s "$CLrefDBD/card.parsed.f11.tab.map"){ 
			system "rm -f $CLrefDBD/card*";
			$DBcmd .= "cp $DBpath/card*.txt $DBpath/card*.map $CLrefDBD\n";
		}
		if ($curDB eq "PTV" && !-s "$CLrefDBD/PATRIC_VF2.tab"){ 
			system "rm -f $CLrefDBD/PATRIC_VF2.tab";
			$DBcmd .= "cp $DBpath/PATRIC_VF2.tab $CLrefDBD\n";
		}
		if ($curDB eq "VDB" && !-s "$CLrefDBD/VF.tab"){ 
			system "rm -f $CLrefDBD/VF.tab";
			$DBcmd .= "cp $DBpath/VF.tab $CLrefDBD\n";
		}
		if ($curDB eq "PAB" && !-s "$CLrefDBD/all_species_data.txt"){
			#copy NOG taxonomy
			my ($DBpathN ,$refDBN ,$shrtDBN) = getSpecificDBpaths("NOG",0);
			$DBcmd .= "cp $DBpathN/all_species_data.txt $CLrefDBD\n" unless (-e "$CLrefDBD/all_species_data.txt");
		}
		if ($curDB eq "TCDB" && !-s "$CLrefDBD/hir.txt"){ 
			$DBcmd .= "cp $DBpath/TCDBhir.txt  $CLrefDBD\n";
		}

		my $jN = "_DIDB$shrtDB$JNUM"; my $tmpCmd;
#		die "$DBcmd";
		if ($DBcmd ne ""){
			($jN, $tmpCmd) = qsubSystem($logDir."DiamondDBprep$shrtDB.sh",$DBcmd,$ncoreDB,int(100/$ncoreDB)."G",$jN,"","",1,\@General_Hosts,\%QSBopt);
			$globalDiamondDependence{$curDB} = $jN;
			#die "$globalDiamondDependence{$curDB}";
		}
		#die $DBcmd."\n";
	}
	return ($refDB,$shrtDB,$clnCmd);
}


sub getRdLibs($ $ $ $){
	my ($ar1,$ar2,$sa1,$mrgHshHR) = @_;
	my @reads1 = @{$ar1}; my @reads2 = @{$ar2}; my @singlRds = @{$sa1};
	my %mrgHsh = %{$mrgHshHR};
	my $mrgMode = 0;
	$mrgMode =1 if (exists ($mrgHsh{mrg}) && $mrgHsh{mrg} ne "");
	my $useLibArrays = 3;
	if ($mrgMode) {$useLibArrays=4;}
	my %ret;
	for (my $kk=0;$kk<$useLibArrays;$kk++){
		my @rds = @singlRds;
		if ($mrgMode){
			if ($kk==1){@rds = $mrgHsh{pair2};}
			if ($kk==2){@rds = $mrgHsh{pair1};}
		} else {
			if ($kk==1){@rds = @reads2;}
			if ($kk==2){@rds = @reads1;}
		}
		if ($kk==3){@rds = $mrgHsh{mrg};}
		$ret{$kk} = \@rds;
	}
	return %ret;
}

sub runOrthoPlacement(){
	my ($ar1,$ar2,$sa1,$mrgHshHR,$outD,$tmpP,$jdep) = @_;
	system "mkdir -p $outD $tmpP" unless (-d $outD && -d $tmpP);
	my %RdLibs = getRdLibs($ar1,$ar2,$sa1,$mrgHshHR);
	my $numCore=22;
	my $scrP = "";my $cmd="";
	$cmd .= "mkdir -p $tmpP\n";
	#my $tmpF = ${$RdLibs{$kk}}[0];
	system "rm -f $tmpP/6fr.fna";
	for (my $kk=0;$kk<scalar(keys(%RdLibs));$kk++){
		my @rds = @{$RdLibs{$kk}};
		$scrP = $rds[0] if ($scrP eq "");
		foreach my $fnaI (@rds){
			$cmd .= "$sdmBin -i $fnaI -o_fna - | $fna2faaBin -q - >> $tmpP/6fr.fna\n";
		}
	}
	$scrP =~ s/\/[^\/]+$//;
	#die $scrP."\n";
	my $hmmscr = "python /g/bork3/home/hildebra/dev/Perl/SoilHelpers/extract_domains.py";
	my $hmmD = "/g/bork3/home/hildebra/DB/HMMs/FungiAB/";
	my @hmmsDB=("Condensation.hmm","dmat.hmm","AMP-binding.hmm","PKS_KS.hmm","Terpene_synth_C.hmm");
	my @hmmNms = ("Condensation","dmat","AMP","PKS","Terpene");
	my @preMSAs = (); #ref alignments, big DB
	my @refTrees = (); #ref trees, calc with fastree
	my $onceExtr=0;
	my $redo=0;
	for (my $i=0; $i<@hmmsDB; $i++){	
		my $hmmM  = "$hmmD/$hmmsDB[$i]";
		my $hmmName = $hmmsDB[$i]; $hmmName=~s/\.hmm//;
		if (!-e "$outD/$hmmName.fna" || $redo){
			$cmd .= "$hmmscr $tmpP/6fr.fna $hmmM $outD/$hmmName.fna $numCore\n" ;
			$onceExtr=1;
		}
	}
	if($onceExtr ==0 && !$redo){
		$cmd = "";
	}
	$cmd .= "mkdir -p $tmpP\n";
		
	#second new part .. alignment to existing tree
	$onceExtr=0;
	for (my $i=0; $i<@hmmsDB; $i++){	
		my $hmmName = $hmmsDB[$i]; $hmmName=~s/\.hmm//;
		my $hmmN2 = $hmmNms[$i];
		my $tarFile = "$outD/$hmmName.fna";
		if (-e $tarFile && -s "$tarFile" == 0){next;}
		#$tarFile = fixHDs4Phylo($tarFile);
		#fix fasta headers
#		$cmd .= "cat $tarFile | perl -p -e 's/[:|#+]/_/g' > $tarFile\n";

		my $clustaloBin = getProgPaths("clustalo");
		my $raxMLbin = getProgPaths("raxml");
		my $treeDBdir = "/g/bork3/home/hildebra/data/SoilABdoms/Jaime/JaimeT2/";
#		my $refTREE = "$treeDBdir/$hmmN2/final_alg/phylo/FASTTREE_allsites.nwk";
		my $refTREE = "$treeDBdir/$hmmN2/final_alg/phylo/IQtree_fast_allsites.treefile";
		my $refMSA = "$treeDBdir/$hmmN2/final_alg/outMSA.faa";
		
		if (!-e "$outD/RAxML_classification.${hmmName}_place"){
			$onceExtr=1;
			$cmd .= "$clustaloBin --p1 $refMSA -i $tarFile --threads $numCore > $tmpP/$hmmName.msa.faa\n";
			$cmd .= "sed -i 's/[:|#+]/_/g' $tmpP/$hmmName.msa.faa\n";
			$cmd .= "rm -f $tmpP/RAxML*\n";
			$cmd .= "$raxMLbin -f v -s $tmpP/$hmmName.msa.faa  -w $tmpP -t $refTREE -m PROTGAMMALG -n ${hmmName}_place -T$numCore\n";
			#$cmd .= "mv $tmpP/RAxML_fastTreeSH_Support.${hmmName}_place $outD/${hmmName}_place.nwk\n";
			$cmd .= "mv $tmpP/*${hmmName}_place $outD/\n";
		}
	}
	
		#die $cmd;
	
	
	$cmd .= "rm -r $tmpP\n";
	#die $cmd;
	my $jobName = "_ORTH$JNUM"; 
	if ($onceExtr){
		my ($jobName2, $tmpCmd) = qsubSystem($logDir."PABpred.sh",$cmd,$numCore,"4G",$jobName,$jdep,"",1,\@General_Hosts,\%QSBopt);
		return $jobName2;
	} else { return "";}
}

sub runDiamond(){
	my ($ar1,$ar2,$sa1,$mrgHshHR,$outD,$CLrefDBD,$tmpP,$jdep,$curDB_o) = @_;
	my %RdLibs = getRdLibs($ar1,$ar2,$sa1,$mrgHshHR);
	
	#die();
	
	my $clnCmd="";my $jobN2="";
	#die;
	system "mkdir -p $outD $tmpP" unless (-d $outD && -d $tmpP);
	#my $diaOfmt = "tab";#old
	#$Query,$Subject,$id,$AlLen,$mistmatches,$gapOpe,$qstart,$qend,$sstart,$send,$eval,$bitSc
	my $diaOfmt = "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore";
	my $ncore = $dia_Cores;
	foreach my $curDB (split /,/,$curDB_o){
		#print "$curDB";
		my ($refDB,$shrtDB,$clnCmd) = prepDiamondDB($curDB,$CLrefDBD,$ncore);
		my $doInterpret = 1;
		#$doInterpret = 0 if ($shrtDB eq "ABR");
		my $getQSeq = 0;
		$getQSeq = 0 if ($curDB eq "PAB");
		my $diaOfmt2 = $diaOfmt;
		$diaOfmt2 .= " qseq" if ($getQSeq); #in case, I want to get the query sequence (matching)
		#run actual diamond
		my @collect = (); my @collectSingl=();
		my $cmd ="mkdir -p $tmpP\n";
		for (my $kk=0;$kk<scalar(keys(%RdLibs));$kk++){
			my $rdsUsed = 0;
			my @rds = @{$RdLibs{$kk}};
			for (my $ii=0;$ii<@rds;$ii++){
				my $query = $rds[$ii];	
				my $outF = "$tmpP/DiaAssignment.sub.$shrtDB.$kk.$ii";
				#my $tmpcnt = `grep -c '^>' $query`; chomp $tmpcnt
				#--comp-based-stats 0

				$cmd .= "$diaBin blastx -f $diaOfmt2 --masking 0 --comp-based-stats 0 --compress 1 --quiet -t $tmpP --min-orf 25 -d $CLrefDBD$refDB.db -q $query -k 5 -e 1e-4 --sensitive -o $outF -p $ncore\n";
				#$cmd .= "$diaBin view -a $outF.tmp -o $outF -f tab\nrm $outF.tmp.daa\n";
				if ($kk==0 || $kk == 3){#single or ext fragments, doesn't need to be sorted
					push(@collectSingl,$outF.".gz");
				} else {
					push(@collect,$outF.".gz");
				}
			}
		}
		
		#die "$cmd\n";
		
		my $out = $outD."dia.$shrtDB.blast";
		my $outgz = "$out.srt.gz";
		#die "$outgz\n";
		#unzip, sort, zip
		$cmd .= "zcat ".join( " ",@collect) ." | sort -t'\t' -k1 -T $tmpP | $pigzBin --stdout -p $ncore > $outgz \n";
		$cmd .= "rm -f ". join( " ",@collect) . "\n";
		if (@collectSingl >= 1){
			#append on gzip, can be done with gzip
			$cmd .= "cat ".join( " ",@collectSingl) ." >> $outgz\nrm -f " . join( " ",@collectSingl) ."\n"; #$out.srt
		}
		$cmd.= "rm -r $tmpP\n";
		#die $cmd."\n";
		my $cmd2 = "$secCogBin -i $outgz -DB $shrtDB -eval $diaEVal -percID $DiaPercID -minAlignLen $DiaMinAlignLen -minFractQueryCov $DiaMinFracQueryCov -mode 0 -LF $CLrefDBD/$refDB.length -reportDomains $getQSeq -DButil $CLrefDBD -tmp $tmpP";
		#$cmd2 .= " " if ($getQSeq);
		if ($curDB eq "ABR"){
			$cmd2 = "$KrisABR $outgz $outD/ABR/ABR.genes.txt $outD/ABR/ABR.cats.txt\n";
		} elsif ($curDB eq "PAB"){ #NOG assignments
			$cmd2 .= " -NOGtaxChk $outD/dia.NOG.blast.srt ";
		}
		$cmd2 .= "\n";
		#if ($doInterpret == 2){
		#	$cmd2 = "$secCogBin $out.gz $shrtDB $diaEVal\n";
		#}
		#$cmd .= "gzip $query"; #WHY???
		
		#check if the secondary routines for parsing blast out still need to be run
		if ($doInterpret){
			if (!(-e  "$out.gz.stone" || -e  "$out.srt.gz.stone" || -e  "$out.stone")){$doInterpret=1;
			} else {$doInterpret=0;
			}
		}
		my $jobName = $jdep;
		my $globDep = $globalDiamondDependence{$curDB};
		$globDep = "" if ($globalDiamondDependence{$curDB} eq "$shrtDB-1");
		
		my $memu = "7G";my $tmpCmd;
		if (!-d $outD || !(-e "$out" || -e "$out.gz"|| -e "$out.srt.gz") ){ #diamond alignments
			$jobName = "_D$shrtDB$JNUM"; 
			($jobName, $tmpCmd) = qsubSystem($logDir."Diamo$shrtDB.sh",$cmd,$ncore,$memu,$jobName,$jdep.";".$globDep,"",1,\@General_Hosts,\%QSBopt);
			$doInterpret=1;#run interpret step in any case
		} else {
			$jobName = $globDep;
		}
		if ($doInterpret){ #parsing of dia output
			my $jobName2 =  "_DP$shrtDB$JNUM";
			$ncore=1; $memu = "30G";
			($jobName, $tmpCmd) = qsubSystem($logDir."Diamo_parse$shrtDB.sh",$cmd2,$ncore,$memu,$jobName2,$jobName,"",1,\@General_Hosts,\%QSBopt) ;
			#die $logDir."ContigStats.sh\n";
			#die "bo";
		}
		if ($jobN2 eq ""){ $jobN2 = $jobName; } else {$jobN2 .= ";".$jobName;}
	}
	return ($jobN2,$clnCmd);
}
sub nopareil(){
	my ($ar1,$outD,$Gdir,$name,$jobd) = @_;
	my $numCore = 4;
	my @re1 = @{$ar1};

	my $sumOut = "$name.npo";
	my $cmd = "mkdir -p $outD\n";
	$cmd .= "$npBin -s $re1[0] -f fastq -t 20 -m 40000 -b $outD$name -n 10240 -i 0.1 -m 0.2\n";#-t $numCore  -o $sumOut
	$cmd .= "cp $outD/$sumOut $Gdir";
	#R part
	#source('/g/bork5/hildebra/bin/nonpareil/utils/Nonpareil.R');
	#Nonpareil.curve('$outD/$sumOut');
	my $jobName = "_NP$JNUM"; my $tmpCmd;
	if (!-d $outD || !-e "$outD/$sumOut"){
		($jobName,$tmpCmd) = qsubSystem($logDir."NonPar.sh",$cmd,1,"42G",$jobName,$jobd,"",1,\@General_Hosts,\%QSBopt);
	}
	return $jobName;
}
sub contigStats(){
	my ($path,$jobd,$cwd,$assD,$subprts,$immSubm,$force, $readLength) = @_;
	
	my $jobName = ""; $QSBopt{LocationCheckStrg}=""; my $tmpCmd="";
	#return;
	system "mkdir -p $cwd" unless ($cwd eq "" || -d $cwd);
	my $cmd = "";
	$cmd .= "mkdir -p $cwd\n" unless ($cwd eq "" );
	$cmd .= "$sepCtsScript $path $assD $subprts $readLength";
	if ($force || (!-d $path."/assemblies/metag/ContigStats/"  || !-s $path."/assemblies/metag/ContigStats/Coverage.count_pergene" || !-s "$path/assemblies/metag/ContigStats/scaff.4kmer" 
			|| !-s "$path/assemblies/metag/ContigStats/ess100genes/ess100.id.txt" && !-s "$path/assemblies/metag/ContigStats/GeneStats.txt")){
		$jobName = "_CS$JNUM"; 
		($jobName,$tmpCmd) = qsubSystem($logDir."ContigStats.sh",$cmd,1,"20G",$jobName,$jobd,$cwd,$immSubm,[],\%QSBopt);
		#print $logDir."ContigStats.sh\n";
	} else {
		$jobName = $jobd;
	}
	return ($jobName,$tmpCmd);
}
sub calcCoverage(){
	my ($cov,$gff,$RL,$cstNme,$jobd) = @_;
	my $jobName = ""; $QSBopt{LocationCheckStrg}=""; my $tmpCmd="";
	my $cmd = "$readCov_Bin $cov $gff $RL";
	if (!-s $cov.".pergene" || !-s $cov.".percontig" || !-s $cov.".median.percontig" ){
		$jobName = "_COV$JNUM";
		$jobName = "$cstNme"."_$JNUM" if ($cstNme ne "");
		#die "$cmd\n";
		($jobName,$tmpCmd) = qsubSystem($logDir."COV$cstNme.sh",$cmd,1,"20G",$jobName,$jobd,"",1,[],\%QSBopt);
		#print $logDir."ContigStats.sh\n";
	} else {
		$jobName = $jobd;
	}
	return ($jobName);
}

sub checkDrives{
	my ($aref) = @_;
	my @locs = @{$aref};
	my $retStr = "\n####### BEGIN file location check ######\n";
	foreach my $llo (@locs){$retStr.="ls -l $llo > /dev/null \n";}
	$retStr.=" \nsleep 3\n"; my $cnt=0;
	foreach my $llo (@locs){ $cnt++;
		$retStr.="if [ ! -d \"$llo\" ]; then echo \'Location $cnt does not exist\'; exit 5; fi\n";
	}
	$retStr .= "####### END file location check ######\n";
	return $retStr;
}
sub adaptSDMopt(){ 
#adaptSDMopt($baseSDMopt,$globalLogDir,$samplReadLength);
	my ($baseSF,$oDir,$RL) = @_;
	my $newSDMf = $oDir."/sdmo_$RL.txt";
	my $nRL = $RL - 10 - int($RL/15);
	open I,"<$baseSF" or die "Can't open sdm opt in:\n $baseSF\n"; my $str = join("", <I>); ;close I;
	if ($RL != 0){
		#$str =~ s/minSeqLength\t\d+/minSeqLength\t$nRL/;
		if ($RL < 50){$str =~ s/maxAccumulatedError\t.*\n/maxAccumulatedError\t0.5\n/;
		} elsif ($RL < 90){$str =~ s/maxAccumulatedError\t\d+\.\d+/maxAccumulatedError\t1.2/;} #really shitty GAII platform
		if ($RL < 90){$str =~ s/TrimWindowWidth	\d+/TrimWindowWidth	8/;$str =~ s/TrimWindowThreshhold	\d+/TrimWindowThreshhold	16/;	
		$str =~ s/maxAmbiguousNT	\d+/maxAmbiguousNT	1/;}
	}
	if ($sdmProbabilisticFilter ==0 ){
		$str =~ s/BinErrorModelAlpha\t.*\n/BinErrorModelAlpha\t-1\n/;
	}
	foreach my $so (keys %sdm_opt){$str =~ s/$so	[^\n]*\n/$so	$sdm_opt{$so}\n/;}
	#die $str."\n";
	open O,">$newSDMf" or die "Can't open new sdm opt out:\n $newSDMf\n"; print O $str; close O;
	#die $newSDMf."\n";
	return $newSDMf;
}

# $sdmjN = cleanInput($cfp1ar,$cfp2ar,$sdmjN,$GlbTmpPath);
 sub cleanInput($ $ $ $){
	my ($cfp1ar,$cfp2ar,$sdmjN,$saveD) = @_;
	my @c1 = @{$cfp1ar}; my @c2 = @{$cfp2ar};
	my $cmd = "";
	for (my $i=0;$i<@c1;$i++){
		if ($c1[$i] =~ m/$saveD/){
			
			$cmd .= "rm -f $c1[$i] $c2[$i]\n" if (-e $c1[$i] || -e $c2[$i]);
		} else {
			#die "$c1[$i] =~ m/$saveD/\n";
		}
	}
	#die $cmd."\n";
	my $jobName = $sdmjN;
	if ($cmd ne ""){
		$jobName = "_PC$JNUM"; my $tmpCmd;
		($jobName, $tmpCmd) = qsubSystem($logDir."ClnUnzip.sh",$cmd,1,"1G",$jobName,$sdmjN,"",1,\@General_Hosts,\%QSBopt);
	}
	return $jobName;
 }
 
 
#Gap Filler to refine scaffolds
sub GapFillCtgs(){
	my($ar1,$ar2,$scaffolds,$GFdir_a,$dep,$xtrTag) = @_; #.= "_GFI1";
	my @pa1 = @{$ar1}; my @pa2 = @{$ar2};
	my @inserts;
	my $prefi = "GF";
	my $numCore = 16;
	mkdir($GFdir_a.$prefi);
	my $log = $GFdir_a.$prefi."/GapFiller.log";
	#system("mkdir -p $GFdir_a$prefi");
	my $GFlib = ($GFdir_a."GFlib.opt");
	my @libFiles;
	for (my $i=0;$i<@pa1;$i++){
		push(@libFiles, ($pa1[$i].",".$pa2[$i]));
		push(@inserts,450);#default value for our hiSeq runs..
	}
	createGapFillopt($GFlib,\@libFiles,\@inserts);
#GF round 1
	my $cmd = "";
	$cmd .= "mkdir -p $GFdir_a$prefi\n";
	$cmd .= $GFbin . " -l $GFlib -s $scaffolds -m 75 -o 2 -r 0.7 -d 70 -t 10 -g 1 -T $numCore -b ".$prefi." -D $GFdir_a > $log \n";
	$cmd .= "rm -r $GFdir_a$prefi/alignoutput $GFdir_a$prefi/intermediate_results $GFdir_a$prefi/reads\n";
	my $finalGFfile = $GFdir_a."$prefi/$prefi.gapfilled.final.fa";
	#die $cmd."\n";
	if ($cmd ne ""){
		my $tmpCmd;
		($dep, $tmpCmd) = qsubSystem($logDir."GapFill_ext_$xtrTag.sh",$cmd,$numCore,int(80/$numCore)."G","_GFE$JNUM",$dep,"",1,[],\%QSBopt);
	}
	return $dep;
}


#scaffolding via mate pairs
sub scaffoldCtgs(){
	my ($ar1,$ar2,$liar, $xar1,$xar2, $refCtgs, $tmpD1,$outD,$dep,$Ncore,$smplName,$spadesRef,$xtraTag) = @_;
	my @pa1 = @{$ar1}; my @pa2 = @{$ar2}; my @libs = @{$liar};
	my @xpa1 = @{$xar1}; my @xpa2 = @{$xar2};
	return ("",$dep) if (@pa1 ==0 );
	my $tmpD = $tmpD1."/scaff/";
	my $bwtIdx = $refCtgs.".bw2"; my $cmdDB="";
	my $clnCmd = ""; my $spadesDir = ""; my $spadFakeDir = "";
	if ($spadesRef ){#&& -e ("$refCtgs/scaffolds.fasta")){#this is supposed to be the spades dir
		my $oldDir = "spades_ori";
		$spadFakeDir = $refCtgs;
		$clnCmd .= "mkdir -p $refCtgs/../$oldDir/; mv $refCtgs/* $refCtgs/../$oldDir/; mv $refCtgs/../$oldDir $refCtgs\n";
		$spadesDir = "$refCtgs$oldDir"; 
		$clnCmd .= "cp $spadesDir/smpls_used.txt $refCtgs\n";
		$refCtgs .= "$oldDir/scaffolds.fasta";
		$clnCmd .="\ngzip $spadesDir/*";
		$clnCmd .="\ngunzip $refCtgs";
		($cmdDB,$bwtIdx) = buildMapperIdx("$refCtgs",$Ncore,0,$MapperProg);#$Ncore);
	} elsif (!-e $bwtIdx){
		($cmdDB,$bwtIdx) = buildMapperIdx("$refCtgs",$Ncore,0,$MapperProg);
	}
	
	
	#my @rd1; my @rd2;
	my $algCmd = "$clnCmd\n$cmdDB\n";
	$algCmd .= "mkdir -p $tmpD\n";
	my @bams; my $cnt=0; my @insSiz; my @orientations;
	for (my $i=0;$i<@pa1;$i++){
		next unless ($libs[$i] =~ m/mate/i);
		#push @rd1,$rds[$i];push @rd2,$rds[$i+1];
		my $tmpOut = "$tmpD/tmpMateAlign$cnt.bam";
		my $tmpBAM = "$tmpD/tmpMateAlign$cnt.srt.bam";
		$algCmd .= "$bwt2Bin --no-unal --end-to-end -p $Ncore -x $bwtIdx -X $mateInsertLength -1 $pa1[$i] -2 $pa2[$i] | $smtBin view -b -F 4 - > $tmpOut\n";
		$algCmd .= "$smtBin sort -@ $Ncore -T kk -O bam -o $tmpBAM $tmpOut; $smtBin index $tmpBAM\n";
		#$algCmd .= "$novosrtBin --ram 50G -o $tmpBAM -i $tmpOut \n";
		$algCmd .= "rm $tmpOut\n\n";
		push(@bams,$tmpBAM); push(@insSiz,10000);push(@orientations,"fr");
		$cnt++;
		#print "sc  mat\n";
	}
	for (my $i=0;$i<@xpa1;$i++){#assumes paired end reads
		#push @rd1,$rds[$i];push @rd2,$rds[$i+1];
		my $tmpOut = "$tmpD/tmpMateAlign$cnt.bam";
		my $tmpBAM = "$tmpD/tmpMateAlign$cnt.srt.bam";
		$algCmd .= "$bwt2Bin --no-unal --end-to-end -p $Ncore -x $bwtIdx  -1 $xpa1[$i] -2 $xpa2[$i] | $smtBin view -b -F 4 - > $tmpOut\n";
		$algCmd .= "$smtBin sort -@ $Ncore -T kk -O bam -o $tmpBAM $tmpOut; $smtBin index $tmpBAM\n";
		#$algCmd .= "$novosrtBin --ram 50G -o $tmpBAM -i $tmpOut \n";
		$algCmd .= "rm $tmpOut\n\n";
		push(@bams,$tmpBAM);push(@insSiz,500);push(@orientations,"fr");
		$cnt++;
		#print "sc  mat\n";
	}
	
	#die "\n\n\n$algCmd\n\n\n";
	return ("",$dep) if (@bams ==0 );
	#create bowtie2 mapping

	my $zcmd = "-z 5000";  #-z 10000";
	 my $ori = "--orientation ".join(" ",@orientations);
	#for (my $i=1;$i<@bams;$i++){ $ori .= " fr"}#$zcmd .= " 10000";
	my $cmd = "";
	my $bams = join(" ",@bams);
	system "mkdir -p $outD" unless (-d $outD);
	$cmd .= "mkdir -p $outD\n";
	$cmd .= "$besstBin $zcmd $ori -f $bams -o $outD -c $refCtgs\n"; #-q $Ncore <- unstable?
	my $jobName = $dep;
	$cmd .= "rm -r $tmpD\n";
	#cleanup2, fake spades result folder
	if ($spadesDir ne ""){
		$cmd .= "mv $outD/BESST_output/pass1/Scaffolds_pass1.fa $spadFakeDir/scaffolds.fasta\n";
		$cmd .= "$renameCtgScr $spadFakeDir/scaffolds.fasta $smplName\n";
		$cmd .= "$sizFiltScr $spadFakeDir/scaffolds.fasta 400 200\n";
		$cmd .= "$assStatScr -scaff_size 500 $spadFakeDir/scaffolds.fasta > $spadFakeDir/AssemblyStats.500.txt\n";
		$cmd .= "$assStatScr $spadFakeDir/scaffolds.fasta > $spadFakeDir/AssemblyStats.ini.txt\n";
		$cmd .= "$assStatScr $spadFakeDir/scaffolds.fasta.filt > $spadFakeDir/AssemblyStats.txt\n\n";
		my ($cmdX,$bwtIdxX) = buildMapperIdx("$spadFakeDir/scaffolds.fasta.filt",$Ncore,0,$MapperProg);
		$cmd .= $cmdX."\n";

	}
	my $newScaffFNA = "$outD/BESST_output/pass2/Scaffolds_pass2.fa";
	$cmd .= "$renameCtgScr $newScaffFNA $smplName\n";
	$cmd .= "\ntouch $outD/scaffDone.sto\n" ;
	$cmd = "" if (-e "$outD/scaffDone.sto");
	
#die "scaff cmd $cmd\n";
	if ($cmd ne ""){
		my $tmpCmd;
		($dep, $tmpCmd) = qsubSystem($logDir."BesstScaff_ext_$xtraTag.sh",$algCmd.$cmd,$Ncore,int(50/$Ncore)."G","_BBE$JNUM$xtraTag",$dep,"",1,[],\%QSBopt);
	}
	return ($newScaffFNA,$dep);
}
#preprocess mate pairs (use nxtrim on them and communicate results)
 sub check_mates($ $ $ $ $){
	my ($ar,$ifastasPre,$mateD,$doMateCln,$dep) = @_;
	my @mat = @{$ar};
	my $cmd = "";
	my @sarPre; my $mateC=0;
	my @mates;
	foreach my $matp (@mat){
		system "mkdir -p $mateD" unless (-d $mateD);
		my @mateX = split /,/,$matp;
		push(@sarPre,"$mateD/mate${mateC}.se.fastq.gz");
		push(@mates,"$mateD/mate.${mateC}_R1.unknown.fastq.gz","$mateD/mate.${mateC}_R2.unknown.fastq.gz","$mateD/mate.${mateC}_R1.mp.fastq.gz","$mateD/mate.${mateC}_R2.mp.fastq.gz");
		next if ( -e "$mateD/matesDone.sto");
		#--rf keeps reads in rf; --joinreads joins pe
		$cmd .= "$nxtrimBin --ignorePF --separate -1 $mateX[0] -2 $mateX[1] -O $mateD/mate.$mateC\n";
		#$nxtrimBin --stdout-mp -1 $rd1 -2 $rd2 | $bwaBin mem $refCtgs -p - > out.sam
		$ifastasPre .= ";$mateD/mate.${mateC}_R1.pe.fastq.gz,$mateD/mate.${mateC}_R1.pe.fastq.gz";
		$mateC++;
	}
	#die "@mates SDS\n";
	$cmd .= "touch $mateD/matesDone.sto\n";
	#die $cmd;
	$cmd = "" if ($doMateCln == 0 || $mateC==0);
	my $jobName = $dep;
	if ($cmd ne ""){
		my $tmpCmd;
		($jobName, $tmpCmd) = qsubSystem($logDir."mateClean.sh",$cmd,1,"1G","_NX$JNUM",$dep,"",1,\@General_Hosts,\%QSBopt);
	}
	return ($ifastasPre,\@sarPre,\@mates,$jobName) ;
 }

 
 #preprocess mate pairs (use nxtrim on them and communicate results)
 sub check_matesL($ $ $ $){
	my ($pa1,$pa2,$mateD,$doMateCln) = @_;
	my %ret;
	my $cmd = "";
	$cmd .= "rm -rf $mateD; mkdir -p $mateD\n";
	 my $mateC=0;
	#foreach my $matp (@mat){
	if ($mateC > 0){die "mate pairs only supports single library\n";}
	system "mkdir -p $mateD" unless (-d $mateD);
	#my @mateX = split /,/,$matp;
	#--rf keeps reads in rf; --joinreads joins pe
	$cmd .= "$nxtrimBin --ignorePF --separate -1 $pa1 -2 $pa1 -O $mateD/mate.$mateC\n";
	$cmd .= "rm -f $pa1 $pa2\n";
	#$nxtrimBin --stdout-mp -1 $rd1 -2 $rd2 | $bwaBin mem $refCtgs -p - > out.sam
	$ret{pe1} = "$mateD/mate.${mateC}_R1.pe.fastq.gz"; $ret{pe2} = "$mateD/mate.${mateC}_R1.pe.fastq.gz";
	$ret{se} =  "$mateD/mate${mateC}.se.fastq.gz";
	$ret{un1} = "$mateD/mate.${mateC}_R1.unknown.fastq.gz"; $ret{un2} = "$mateD/mate.${mateC}_R2.unknown.fastq.gz";
	$ret{mp1} = "$mateD/mate.${mateC}_R1.mp.fastq.gz"; $ret{mp2} = "$mateD/mate.${mateC}_R2.mp.fastq.gz";
	$mateC++;
	#}
	#die "@mates SDS\n";
	my $locStone = "$mateD/matesDone.sto";
	$cmd .= "touch $locStone\n";
	#die $cmd;
	$cmd = "" if ($doMateCln == 0 || $mateC==0);
	
	return (\%ret,$cmd,$locStone) ;
 }

 
 #determines what read types are present and starts cleaning of mates, if required
 sub get_ifa_mifa($ $ $ $ $ $ $){
	my ($ifastas,$ifastasS,$libInfoAr, $mateD, $doMateCln, $jdep, $singlReadMode) = @_;
	my @allFastas = split /;/,$ifastas;
	my @libInfo = @{$libInfoAr}; my @miSeqFastas = (); my $mcnt=0;
	my @mates;
	#die "@libInfo\n";
	foreach (@libInfo){
		if ($_ =~ m/.*miseq.*/i) {
			push (@miSeqFastas, $allFastas[$mcnt]);
			splice(@allFastas, $mcnt, 1);
		} elsif ($_ =~ m/.*mate.*/i){ #remove from process
			push (@mates, $allFastas[$mcnt]);
			splice(@allFastas,$mcnt,1);
		}
		$mcnt++;
	}
	$ifastas = join(";",@allFastas);
	my $mi_ifastas = join(";",@miSeqFastas);
	my $singleIfas = $ifastasS; my $matRef = [];
	#die "$ifastas\n$singleIfas\n\n";
	#moved to seedUnzip2tmp
	#($ifastas,$singleAddAr,$matRef,$jdep) = check_mates(\@mates,$ifastas,$mateD,$doMateCln,$jdep);

	return ($ifastas, $mi_ifastas, $singleIfas, $matRef, $jdep);
 }
 sub get_sdm_outf($ $ $ $ $){
	my ($ifastas, $mi_ifastas,$finD,$singlReadMode,$pairedReadMode) = @_;
	my @ret1;my @ret2;my @sret;
	my $fEnd = "fq";
 	if ($gzipSDMOut){
		$fEnd = "fq.gz";
	}
	
	if ( $pairedReadMode){
		push(@ret1,$finD."filtered.1.$fEnd");push( @ret2, ($finD."filtered.2.$fEnd"));push(@sret, ($finD."filtered.singl.$fEnd"));
	} 
	if ($singlReadMode && !$pairedReadMode){ #only single reads avaialble, different file ending..
		push(@sret, $finD."filtered.s.$fEnd");
	}
	if ($mi_ifastas ne ""){
		push(@ret1,$finD."filtered_mi.1.$fEnd");push( @ret2, ($finD."filtered_mi.2.$fEnd"));push(@sret, ($finD."filtered_mi.singl.$fEnd"));
	}
	
	return (\@ret1,\@ret2,\@sret);
}
 sub check_sdm_loc(){
	die "defunct functon  check_sdm_loc!\n";
	my ($ar1,$ar2,$libInfoAr,$sdmO) = @_;
 	my $ifastasPre = ${$ar1}[0].",".${$ar2}[0];
	for (my $i=1;$i<@{$ar1};$i++){if ($i>0){$ifastasPre .= ";".${$ar1}[$i].",".${$ar2}[$i];}}
	my ($ifastas, $mi_ifastas, $singlAddAr, $matAr, $jdep) = get_ifa_mifa($ifastasPre,"",$libInfoAr,"",0,"","???");
	my ($ar1x,$ar2x,$sar) = get_sdm_outf($ifastas, $mi_ifastas,$sdmO,"???","");
	my @ret1=@{$ar1x};my @ret2=@{$ar2x};my @sret=@{$sar};
	my $presence=1;
	foreach my $loc (@ret2,@ret1){	if (!-e $loc || -z $loc){$presence=0;}	}
	#for (my $i=0;$i<;$i++){	if ( !-e $ret2[0]|| -z $ret1[0]){$presence=0;}	}
	if (!-e $sret[0]){$presence=0;}
	my $stone = "$sdmO/filterDone.stone";
	if (!-e $stone){$presence=0;}
	if (!$presence){return 0;}
	my $assInputFlaw = 0;
	if (-e $logDir."spaderun.sh.otxt"){open I,"<$logDir/spaderun.sh.otxt" or die "Can't open old assembly logfile $logDir\n"; my $str = join("", <I>); close I;
		if ($str =~ /Assertion `seq_\.size\(\) == qual_\.size\(\)' failed\./){$assInputFlaw=1;}	
		if ($str =~ /paired_readers\.hpp.*Unequal number of read-pairs detected in the following files:/){$assInputFlaw=1;}	
	}

	if ($presence==0 || $assInputFlaw==1){
		return 0;
	} else {
		return 1;
	}
}

#($mergRdsHsh,$mergJbN) = mergeReads($arp1,$arp2,$sdmjN,$GlbTmpPath."merge_clean/");
sub mergeReads(){
	my ($arp1,$arp2,$jdep,$outdir,$doMerge,$runThis) = @_;
	my $numCores = 8;
	my $outT = "sdmCln";
	my %ret = (mrg => "", pair1 => "", pair2 => "");
	#print "XSADS\n!$doMerge || !$readsRpairs || !$runThis\n";
	if (!$doMerge || !$readsRpairs || @{$arp2} == 0 || !$runThis){return (\%ret,"");}
	#print "XSADS1\n";
	if (@{$arp1} > 1 ){die "Array with reads provided to merging routine is too large!\n@{$arp1}\n";}
	my $mergCmd = "$flashBin -M 250 -z -o $outT -d $outdir -t $numCores ${$arp1}[0] ${$arp2}[0]\n";
	my $stone = "$outdir/$outT.sto";
	$mergCmd .="touch $stone\n ";
	my $jobName = "";
	if (-e $stone && -e "$outdir/$outT.extendedFrags.fastq" && !-e "$outdir/$outT.extendedFrags.fastq.gz"){
		#zip
		$mergCmd = "$pigzBin -p $numCores $outdir/$outT.extendedFrags.fastq $outdir/$outT.notCombined_1.fastq $outdir/$outT.notCombined_2.fastq\n";
		system "rm $stone";
	}
	if (!-e $stone){
		$jobName = "_FL$JNUM"; my $tmpCmd;
		($jobName, $tmpCmd) = qsubSystem($logDir."flashMrg.sh",$mergCmd,$numCores,"3G",$jobName,$jdep,"",1,[],\%QSBopt);
	}
	
	#die "$logDir/flashMrg.sh\n$mergCmd\n";
	$ret{mrg} = "$outdir/$outT.extendedFrags.fastq.gz";
	$ret{pair1} = "$outdir/$outT.notCombined_1.fastq.gz";
	$ret{pair2} = "$outdir/$outT.notCombined_2.fastq.gz";
	return (\%ret,$jobName);
}
 
sub sdmClean(){
	my ($curOutDir,$ar1,$ar2,$ars,$libInfoAr,$tmpDX,$mateD,$finD,$sdmO,$jobd,$runThis) = @_;
	#create ifasta path
	#die "cllll\n";
	my $comprCores=1;
	if (@{$ar1} == 0 && @{$ars}==0){die "Empty array to sdmClean given\n";}
	my $ifastasPre="";my $ifastasPreS=""; my $singlReadMode=0; my $pairReadMode=0;
	if (@{$ar1} != 0){
		$ifastasPre = ${$ar1}[0].",".${$ar2}[0]; $pairReadMode=1;
		for (my $i=1;$i<@{$ar1};$i++){if ($i>0){$ifastasPre .= ";".${$ar1}[$i].",".${$ar2}[$i];}}
		#die "${$ar1}[0]\n";
	} 
	if (@{$ars} > 0)	{
		$ifastasPreS = ${$ars}[0];
		for (my $i=1;$i<@{$ars};$i++){if ($i>0){$ifastasPreS .= ";".${$ars}[$i];}}
		$singlReadMode=1;
		
	}
	if (!$singlReadMode && !$pairReadMode){
		die "Couldn't find any calid input files (sdmClean)\n";
	}
	#die "$pairReadMode\n$singlReadMode\n";
	my $stone = "$finD/filterDone.stone";
	open O,">$curOutDir/input_fil.txt"; print O $ifastasPre; close O;

	#system("mkdir -p $finD");
	my $cmd = "";
	#$cmd .= "mkdir -p $tmpD\n" unless ($tmpD eq "");
	$cmd .= "mkdir -p $finD\n" unless ($finD eq "");
	$cmd .= "rm -f $stone\n";
	$cmd .= "mkdir -p $logDir/sdm/\n";
	
	my ($ifastas, $mi_ifastas, $singlIfas, $matAr, $jdep) = get_ifa_mifa($ifastasPre,$ifastasPreS,$libInfoAr,$mateD,0,$jobd,$singlReadMode);
	$jobd = $jdep; #replaces old dep
	#die "$ifastas\n";
	my ($ar1x,$ar2x,$sar) = get_sdm_outf($ifastas, $mi_ifastas,$finD,$singlReadMode,$pairReadMode);
	
	#push(@{$sar},@{$singlAddAr});
	my @ret1=@{$ar1x};my @ret2=@{$ar2x};my @sret=@{$sar};
	
	#die "$mi_ifastas\n$ifastas XX\n@ret1\n@sret\n";
	#$baseSDMoptMiSeq;
	my $ofiles = "";
	my $mi_ofiles = "";
	#system("mkdir -p $logDir/sdm/") unless (-d "$logDir/sdm/");
	my $useLocalTmp = 1;
	#if ($tmpD eq ""){$useLocalTmp = 0;$tmpD = $finD;}
	#my $nsdmPair = 2;
	my $sdm_def= " -ignore_IO_errors 1 -i_qual_offset auto -binomialFilterBothPairs 1 ";
	my $catCmd = "cat ";
	#$catCmd = "$pigzBin -p $comprCores -c " if ($gzipSDMOut);
	if ($pairReadMode){
		$ofiles = $ret1[0].",".$ret2[0];# $finD."/filtered.1.fq,".$finD."/filtered.2.fq";
		$cmd .= "$sdmBin -i \"$ifastas\" -o_fastq $ofiles -options $sdmO -paired 2  -log $logDir/sdm/filter.log $sdm_def\n\n";
		#push(@ret1,$finD."filtered.1.fastq");push( @ret2, ($finD."filtered.2.fastq"));push(@sret, ($finD."filtered.singl.fastq"));
		my $cmdSA = "$catCmd $ret1[0] " ;#replace with stars and singl
		if ($gzipSDMOut){$cmdSA =~ s/\.\d\.fq\.gz/\.\*\.singl\.fq\.gz/g ;
		} else {$cmdSA =~ s/\.\d\.fq/\.\*\.singl\.fq/g ;	}
		my @tmp = split /\s+/,$cmdSA;
		$cmd .= $cmdSA . ">>  $sret[0]\n" ;
		$cmd .= "rm -f $tmp[1]\n";
	}
	if ($singlReadMode){
		my $tmpO = $sret[0];$tmpO =~ s/(.*)\//$1\/tmp\./;
		#die $tmpO."\n";
		$cmd .= "$sdmBin -i \"$singlIfas\" -o_fastq $tmpO -options $sdmO -paired 1  -log $logDir/sdm/filterS.log $sdm_def\n\n";
		if ($pairReadMode){
			$cmd .= "$catCmd $tmpO >>  $sret[0]\nrm $tmpO\n" ;
		} else {
			$cmd .= "mv $tmpO $sret[0]\n";
		}
		
	}
	if ($mi_ifastas ne ""){
		$mi_ofiles =  $ret1[1].",".$ret2[1];#$tmpD."/filtered_mi.1.fastq,".$tmpD."/filtered_mi.2.fastq";
		#$cmd .= "touch $tmpD/filtered_mi.1.fastq.singl  $tmpD/filtered_mi.2.fastq.singl\n";
		$cmd .= " $sdmBin -i \"$mi_ifastas\" -o_fastq $mi_ofiles -options $baseSDMoptMiSeq -paired 2  -log $logDir/sdm/filter_xtra.log $sdm_def\n\n";
		#$cmd .= "/g/bork3/home/hildebra/dev/C++/sdm/./sdm -i_fastq \"$mi_ifastas\" -o_fastq $ofiles -options $baseSDMoptMiSeq -paired 2 -i_qual_offset auto -log $logDir/sdm/filter.log -binomialFilterBothPairs 1\n\n";
		#push(@ret1,$finD."filtered_mi.1.fastq");push( @ret2, ($finD."filtered_mi.2.fastq"));push(@sret, ($finD."filtered_mi.singl.fastq"));
#		$cmd .= "$catCmd $tmpD/filtered_mi.1.fastq.singl  $tmpD/filtered_mi.2.fastq.singl > $sret[1]\n";
		if (!$singlReadMode){
			my $cmdSA = "$catCmd $ret1[1] ";
			if ($gzipSDMOut){
				$cmdSA =~ s/\.\d\.fq\.gz/\.\*\.singl\.fq\.gz/g ;
			} else {
				$cmdSA =~ s/\.\d\.fq/\.\*\.singl\.fq/g ;
			}
			$cmd .= $cmdSA . ">>  $sret[1]\n" ;
		}
	}
	#die $cmd."\n";
#	if ($useLocalTmp){
#		if ($unpackZip || $gzipSDMOut){#zip output
#			foreach my $of (split(/,/,$ofiles)){
#				$of =~ m/\/([^\/]+$)/; my $fname = $1;
#				$cmd .= "$pigzBin -p $comprCores -c $of > $finD/$fname.gz\n";
#			}
#			if (!$singlReadMode){
#				$sret[-1] =~ m/\/([^\/]+$)/; my $fname = $1;
#				#$cmd .= "$pigzBin -p $comprCores -c ".$sret[-1]." > $finD/$fname.gz\n" ;
#			}
#		} else {
#			$cmd .= "mv -f ".join(" ",(split(/,/,$ofiles),split(/,/,$mi_ofiles)))." $finD\n";
#			$cmd .= "rm -rf $tmpD\n";
#		}
#	} elsif ($unpackZip || $gzipSDMOut){#zip output
#		foreach my $of (split(/,/,$ofiles)){
#			$of =~ m/\/([^\/]+$)/; my $fname = $1;
#			$cmd .= "$pigzBin -p $comprCores $of \n";
#		}
#		if (!$singlReadMode){
#			$sret[-1] =~ m/\/([^\/]+$)/; my $fname = $1;
#			#$cmd .= "$pigzBin -p $comprCores ".$sret[-1]." \n" ;
#		}
#	}
	if (!$singlReadMode){
		$sret[-1] =~ m/\/([^\/]+$)/; my $fname = $1;
		#$cmd .= "$pigzBin -p $comprCores ".$sret[-1]." \n" ;
	}
	$cmd .= "touch $stone\n";
	#die "$cmd\n";
	my $jobName = "";
	my $presence=1; my $gzPres=1;
	if (!$unpackZip){
		foreach my $loc (@ret2,@ret1){	if (!-e $loc || -z $loc){$presence=0;} my $loc2 = $loc;$loc2 =~ s/\.gz$//;	if (!-e $loc2){$gzPres=0;}}

		#for (my $i=0;$i<@ret1;$i++){	if (!-e $ret1[$i] || -z $ret1[$i]){system "rm -f $ret1[$i] $stone";$presence=0;}	}
		#for (my $i=0;$i<@ret2;$i++){	if ( !-e $ret2[$i]|| -z $ret1[$i]){system "rm -f $ret2[$i] $stone";$presence=0;}	}
		if (!-e $sret[0]){$presence=0;}
	}
	if (!-e $stone){$presence=0;}
	
	#recovery part, that uses previous sdm filtered data..
	if (!$presence && $gzPres && -e $stone){
		#exists, but not gzipped..
		$cmd = "";
		foreach my $loc (@ret2,@ret1,@sret){
			my $loc2 = $loc;
				$loc2 =~ s/\.gz$//;
			$cmd .= "$pigzBin -p $comprCores $loc2\n";
		}
	}
	#die "$presence\n";
	
	#common error: spade input failed
	my $assInputFlaw = 0;
	if (-e $logDir."spaderun.sh.otxt"){open I,"<$logDir/spaderun.sh.otxt" or die "Can't open old assembly logfile $logDir\n"; my $str = join("", <I>); close I;
		if ($str =~ /Assertion `seq_\.size\(\) == qual_\.size\(\)' failed\./){$assInputFlaw=1;}	
		if ($str =~ /paired_readers\.hpp.*Unequal number of read-pairs detected in the following files:/){$assInputFlaw=1;}	
	}
	
	if (-e $logDir."megahitrun.sh.etxt"){open I,"<$logDir/megahitrun.sh.etxt" or die "Can't open old assembly logfile $logDir\n"; my $str = join("", <I>); close I;
		#if ($str =~ /Unequal /){$assInputFlaw=1;}	#have to really look this up...
	}
	#die("ass inp flaw: $assInputFlaw\n");
	#die "($presence==0 || $assInputFlaw==1 )&& $runThis\n";
	if ( ($presence==0 || $assInputFlaw==1 )&& $runThis){
		#die "yes\n";
		$jobName = "_SDM$JNUM"; my $tmpCmd;
		($jobName, $tmpCmd) = qsubSystem($logDir."sdmReadCleaner.sh",$cmd,1,"15G",$jobName,$jobd.";".$jdep,"",1,\@General_Hosts,\%QSBopt);
	}
	#die "$presence presi\n@ret1\n";
	
	return (\@ret1,\@ret2,\@sret,$matAr,$jobName);
}
#$importMocat==1
sub mocat_reorder(){
	my($ar1,$ar2,$singlAr,$inJob) = @_;
	
	#my @pairs = split(";",$ifastas);
	my @ret1 = @{$ar1}; my @ret2 = @{$ar2}; 
	#print "@ret1\n@ret2\n";
	#foreach (@pairs){		my @spl = split /,/;		push(@ret1,$spl[0]);push(@ret2,$spl[1]);	}
	#my $jobName = $inJob;
	return (\@ret1,\@ret2,$singlAr,$inJob);
}
sub SEEECER(){
	my ($p1ar,$p2ar,$tmpD) = @_;
	die("SEECER deactive\n");
	my @p1 = @{$p1ar}; my @p2 = @{$p2ar};
	if ( $p1[0] =~ m/.*\.gz/){
		system("gunzip -c ".join(" ",@p1)." > $tmpD/pair.1.fastq");	system("gunzip -c ".join(" ",@p2)." > $tmpD/pair.2.fastq");
		@p1 = ("$tmpD/pair.1.fastq"); @p2 = ("$tmpD/pair.2.fastq");
	} elsif ( @p1 > 1 ){
		system("cat ".join(" ",@p1)." > $tmpD/pair.1.fastq");	system("cat ".join(" ",@p2)." > $tmpD/pair.2.fastq");
		@p1 = ("$tmpD/pair.1.fastq"); @p2 = ("$tmpD/pair.2.fastq");
	}
	my $SEEbin = "bash /g/bork5/hildebra/bin/SEECER-0.1.3/SEECER/bin/run_seecer.sh";
	system("mkdir -p $tmpD/tmpS");
	my $cmd = $SEEbin . " -t $tmpD/tmpS $p1[0] $p2[0]";
	#qsubSystem($logDir."SEECERCleaner.sh",$cmd,1,"30G",1);
	my @ret1= ($tmpD."pair.1.fastq_corrected.fa");my @ret2= ($tmpD."pair.2.fastq_corrected.fa");
	return (\@ret1,\@ret2);
}
sub complexGunzCpMv($ $ $ $){
	my ($fastap,$in,$GlbTmpPath,$finDest) = @_;
	my $unzipcmd = "";
	
	
	if (0&&$in =~ m/\.gz$/){ #deactivated.. takes too much space on file sys
		$unzipcmd .= "gunzip -c $fastap$in";
		$in =~ s/\.gz$//;
		$unzipcmd .= " > $finDest$in \n";
		
	} else {
		$unzipcmd .= "cp $fastap$in $finDest\n";
	}
	if (0 && $GlbTmpPath ne $finDest){
		$unzipcmd .= "mv -f $GlbTmpPath$in $finDest\n";
		die "$GlbTmpPath ne $finDest";
	}
	my $newRDf = $finDest."$in";
	
	return ($unzipcmd,$newRDf);
}

sub outfiles_trimall($ $){
	my ($opath,$fil) = @_;
	my $OFp1 = "$opath/$fil"; 
	my $OFu1 = "$opath/$fil";	
	if ($OFu1 =~ m/\.gz$/){
		$OFu1 =~ s/(\.[^\.]+\.gz)$/\.sing$1/ ;#$OFp1 =~ s/\.gz$// 
	} elsif ($OFu1 =~ m/\.f[^\.]*q$/){
		$OFu1 =~ s/(\.f[^\.]*q)$/\.sing$1/ ;
	} else {
		die "Unknown file ending: $fil\n";
	}
	#die "$OFp1\n$OFu1\n";
	return ($OFp1,$OFu1);
}

sub seedUnzip2tmp(){
	my ($fastp,$curSmpl,$jDepe,$tmpPath,$finDest, $WT,$mocatImport,$libNum,$calcUnzp) = @_;
	my $smplPrefix = $map{$curSmpl}{prefix};
	my $xtrMapStr = $map{$curSmpl}{SupportReads};
	my $doMateCln = 1; #nxtrim  mate pairs ?
	my $numCore=$unzipCores;
	my $rawReads=""; my $mmpu = "";
	my $fastp2 = ""; my $xtraRdsTech = "";
	$xtrMapStr = "" if (!defined $xtrMapStr) ;
	if ( $xtrMapStr ne ""){
		#die "XX$xtrMapStr\n";
		my @spl = split(/:/,   $map{$samples[$JNUM]}{"SupportReads"}   );
		if (@spl > 1){
			$xtraRdsTech = $spl[0].$libNum;
			$fastp2 = $spl[1];
		}
		#die $fastp2."\n".$xtraRdsTech."\n";
	}
	#die "$fastp\n";
#$fastp = "/g/bork1/coelho/DD_DeCaF/eggnog-simulations/simulated-samples/sample-0/";
	if ($fastp eq "") { print "No primary dir.. \n"; }
	#if ($fastp ne "") {print "Looking for fq.gz in ".$fastp;} else { print "No primary dir.. "; }
	#if ($fastp2 ne ""){ print " and $fastp2";}
	#print "\n";
	#die "$fastp\n";
	my @pa1; my @pa2; my @pas; my @paX1; my @paX2;
	if ($fastp ne ""){
		if ($mocatImport==0){
			#print "$fastp\n";
			#die "$smplPrefix$rawFileSrchStr2\n";
			opendir(DIR, $fastp) or die "Can't find: $fastp\n";	
			if ($rawFileSrchStrSingl ne ""){
				@pas = sort ( grep { /$smplPrefix$rawFileSrchStrSingl/  && -e "$fastp/$_"} readdir(DIR) );	rewinddir DIR;
			}
			if ($readsRpairs!=0){
				@pa2 = sort ( grep { /$smplPrefix$rawFileSrchStr2/ && -e "$fastp/$_" } readdir(DIR) );	rewinddir DIR;
				@pa1 = sort ( grep { /$smplPrefix$rawFileSrchStr1/  && -e "$fastp/$_"} readdir(DIR) );	rewinddir(DIR);
			}
			close(DIR);
			
			
			#sort out multi assignments of read files (grep not uniquely defined)
			if ($rawFileSrchStrSingl ne ""){
				my %h;
				if ($prefSinglFQgreps){
					@h{(@pas)} = undef;
					@pa1 = grep {not exists $h{$_}} @pa1;
					@pa2 = grep {not exists $h{$_}} @pa2;
				} else {
					@h{(@pa1,@pa2)} = undef;
					@pas = grep {not exists $h{$_}} @pas;
				}
			}

			#die "@pas\n@pa1\n@pa2\n";
			
			#print readdir(DIR);
		} else {
			$fastp .= $map{mocatFiltPath}; 
			opendir(DIR, $fastp) or die "$!\n$fastp\n";;	
			@pas = sort ( grep { /.*single\.f[^\.]*q\.gz$/  && -e "$fastp/$_"} readdir(DIR) );	rewinddir DIR;
			@pa2 = sort ( grep { /.*\.2\.f[^\.]*q\.gz$/ && -e "$fastp/$_" } readdir(DIR) );	rewinddir DIR;
			@pa1 = sort ( grep { /.*\.1\.f[^\.]*q\.gz$/  && -e "$fastp/$_"} readdir(DIR) );	rewinddir DIR;
			close(DIR);
			#print "@pa2  XX\n";
		}
	}
	#die "@pa1\n@pas\n";
	#import xtra long rds
	if (@pa1 != @pa2 && $readsRpairs!=0){die "For dir $fastp, unequal fastq files exist:\nP1\n".join("\n",@pa1)."\nP2:\n".join("\n",@pa2)."\n";}
	#check for date of files (special filter)
	if ($doDateFileCheck){
		my @pa1t = @pa1; my @pa2t = @pa2; undef @pa1; undef @pa2;
		for (my $i=0; $i<@pa1t;$i++){
			my $date = POSIX::strftime( "%m", localtime( ( stat "$fastp/$pa1t[$i]" )[9] ) );
			#print $date;
			if ($date < 3){push(@pa1, $pa1t[$i]);push(@pa2, $pa2t[$i]);}
		}
		if (@pa1 != 1){die "still too many file: $fastp\n @pa1\n@pa2\n";}
	}
	my @libInfo = ("lib$libNum") x int @pa1;
	if (@pa1==0 && @pas!=0 || @pas > @pa1){#case of just single read in metag
		@libInfo = ("lib$libNum") x int @pas;
	}
	if ($fastp2 ne ""){
		opendir(DIR, $fastp2) or die $!;	
		@paX2 = sort ( grep { /$rawFileSrchStrXtra2/ && -e "$fastp2/$_" } readdir(DIR) );	rewinddir DIR;
		@paX1 = sort ( grep { /$rawFileSrchStrXtra1/  && -e "$fastp2/$_"} readdir(DIR) );	close(DIR);
		if (@paX2 != @paX1){die "For dir $fastp, unequal fastq files exist:P1\n".join("\n",@paX1)."\nP2:\n".join("\n",@paX2)."\n";}
		if (@paX2 == 0){die "Can't find files with pattern $rawFileSrchStrXtra2 in $fastp2\n";}
		#die $paX1[0]."\n";
		push @pa1 , @paX1; push @pa2 , @paX2; my @lib2 = $xtraRdsTech x @paX1; push @libInfo, @lib2;
	}
		#die "@libInfo\n$libInfo[1]\n";

	#die "@pa1";
	#die "For dir $fastp, unual fastq files exist:P1\n".join("\n",@pa1)."\nP2:\n".join("\n",@pa2)."\n";
	
	#check if symlink and if this is valid & create raw read link:
	for (my $i = 0; $i<@pa1; $i++){
		my $pp = $fastp;
		$pp = $fastp2 if ($libInfo[$i] eq $xtraRdsTech);
		if (-l $pp.$pa1[$i]){
			if (!-f abs_path($pp.$pa1[$i])){die "File $pa1[$i] is not file.\n";}
		}
		if (-l $pp.$pa2[$i]){
			if (!-f abs_path($pp.$pa2[$i])){die "File $pa2[$i] does not exist.\n";}
		}
		if ($i==0){
			$rawReads="$pp$pa1[$i],$pp$pa2[$i]";
		} else {
			$rawReads.=";".$pp.$pa1[$i].",".$pp.$pa2[$i];
		}
#		print "$pp$pa1[$i]\n";
		my $realP = `readlink -f $pp$pa1[$i]`;
		if (defined $realP && $realP =~ m/\/(MMPU[^\/]+)\//){
			$mmpu = $1;
		}
	}
	#die $rawReads."\n";
	#DEBUG fix to reduce file sizes
	#@fastap2 = ($fastap2[0]); @fastap1 = ($fastap1[0]);
	if (@pa1 == 0 && @pas ==0 ){die"Can;t find files in $fastp\nUsing search pattern: $smplPrefix$rawFileSrchStr1  $smplPrefix$rawFileSrchStr2\n";}
	my $finishStone = "$finDest/rawRds/done.sto";
	my $trimoStone = $finishStone;
	if ($useTrimomatic){
		$trimoStone = "$finDest/rawRds/trimomatic.sto";
	}

	$tmpPath.="/rawRds/";
	my $unzipcmd = "";
	$unzipcmd .= "set -e\n"; #sleep $WT\n
	$unzipcmd .= "rm -f $finishStone $trimoStone\nrm -r -f $tmpPath $finDest/rawRds/\nmkdir -p $tmpPath\nmkdir -p $finDest/rawRds/\n";

	#make sure input is unzipped
	#die ($tmpPath."\n");
	#system("mkdir -p $finDest/rawRds/");# my $newRDf ="";
	my $testf1 = "";my $testf2 = "";
	my $illCLip = $himipeSeqAd;
	if ($map{$curSmpl}{clip} ne ""){$illCLip = $map{$curSmpl}{clip};}
	for (my $i=0; $i<@pa1; $i++){
		#print $pa1[$i]."\n";
		my $pp = $fastp."/";
		if ($filterFromSource){
			$pa1[$i] = $pp.$pa1[$i]; $pa2[$i] = $pp.$pa2[$i];
		} elsif ($useTrimomatic){
			$pp = $fastp2 if ($libInfo[$i] eq $xtraRdsTech);
			#trimomatic instead of unzip
			my ($OFp1,$OFu1) = outfiles_trimall("$finDest/rawRds/",$pa1[$i]);
			my ($OFp2,$OFu2) = outfiles_trimall("$finDest/rawRds/",$pa2[$i]);
			$unzipcmd .= "java -jar $trimJar PE -threads $numCore $pp/$pa1[$i] $pp/$pa2[$i] $OFp1 $OFu1 $OFp2 $OFu2 ILLUMINACLIP:$illCLip:2:30:10\n";
			#for now: discard of singletons
			$unzipcmd .= "rm $OFu1 $OFu2\n";
			$pa1[$i] = $OFp1; $pa2[$i] = $OFp2;
		} else {
		#old style
			my ($tmpCmd,$newF) = complexGunzCpMv($pp,$pa1[$i],$tmpPath,$finDest."/rawRds/");
			$unzipcmd .= $tmpCmd."\n";
			$pa1[$i] = $newF;
			($tmpCmd,$newF) = complexGunzCpMv($pp,$pa2[$i],$tmpPath,$finDest."/rawRds/");
			$unzipcmd .= $tmpCmd."\n";
			$pa2[$i] = $newF;
		}
	}
	$unzipcmd .= "chmod +w ".join(" ",@pa1)."\n" if (@pa1>0);
	$unzipcmd .= "chmod +w ".join(" ",@pa2)."\n" if (@pa2>0);
	#die "$unzipcmd\n";
	#die "@pa1\n";
	for (my $i=0; $i<@pas; $i++){
		my $pp = $fastp;
		#print "$libInfo[$i] eq $xtraRdsTech\n";
		$pp = $fastp2 if ($libInfo[$i] eq $xtraRdsTech);
		if ($filterFromSource){
			$pas[$i] = $pp.$pas[$i]; 
		} else {
			my ($tmpCmd,$newF) = complexGunzCpMv($pp,$pas[$i],$tmpPath,$finDest."/rawRds/");
			$unzipcmd .= $tmpCmd."\n";
			$pas[$i] = $newF;
			if ($splitFastaInput != 0){ #in case of input assemblies (MG-RAST.. arghh!!)
				$unzipcmd .= "\n$sizSplitScr $pas[$i] $splitFastaInput\n";
			}
		}
	}

	$unzipcmd .= "touch $finishStone\n";
	if ($useTrimomatic){
		$unzipcmd .= "touch $trimoStone\n" ;
	}
	my $jobN = "";
	my $jobNUZ = $jobN;
	
	#die "X";
	#die $unzipcmd."\n";
	#print "  HH ".-s $testf2 < -s $testf1." FF \n";
	my $tmpCmd;
	#die "$unzipcmd\n$calcUnzp\n";
	if ($calcUnzp && !$filterFromSource){ #submit & check for files
		my $presence=1;
		for (my $i=0;$i<@pa1;$i++){	if (!-e $pa1[0] || -z $pa1[0]){$presence=0; }	}#die "$pa1[0]\n";
		for (my $i=0;$i<@pa2;$i++){	if ( !-e $pa2[0] || -z $pa2[0]){$presence=0;}	}
		if (!$presence || !-e $finishStone  || !-e $trimoStone){
			$jobN = "_UZ$JNUM"; 
			my $tmpSHDD = $QSBopt{tmpSpace};
			#die "unzip\n";
			#print "$unzipcmd\n";
			$unzipcmd = "" if ($presence && -e $finishStone && -e $trimoStone);
			$QSBopt{tmpSpace} = "150G"; #set option how much tmp space is required, and reset afterwards
			($jobN, $tmpCmd) = qsubSystem($logDir."UNZP.sh",$unzipcmd,$numCore,"20G",$jobN,$jDepe,"",1,\@General_Hosts,\%QSBopt) ;
			#### 1 : UNZIP
			$QSBopt{tmpSpace} = $tmpSHDD;
			$WT += 30;
			#print " FDFS ";
		}
	#	die($jobN);
		#### 2 : remove human contamination
		#DB just needs to be loaded way too often.. do after sdm to have single files
		#$jobN = krakHSap(\@pa1,\@pa2, \@pas,$tmpPath,$jobN);
	}
	
		#check already here for mate pair support reads, deactivate fastp2
	my ($mateCmd,$mateSto) = ("","/sh");
#	print "@libInfo\n";
	my $ii=0; my @matePrps;
	while($ii<@libInfo){
		#print $ii." \n";
		#next;
		unless ($libInfo[$ii] =~ m/.*mate.*/i){$ii++;next;} #remove from process
		my $href;
		($href,$mateCmd,$mateSto) = check_matesL($pa1[$ii],$pa2[$ii],$finDest."mateCln/",$doMateCln);
		#remove this ori file from raw reads
		splice(@pa1,$ii,1);splice(@pa2,$ii,1);splice(@libInfo,$ii,1);
		push(@matePrps,$href);
	}
	if ( ($mateSto ne "/sh" && !-e $mateSto) && $calcUnzp){
		$mateCmd = "" if ( -e $mateSto);
		($jobN, $tmpCmd) = qsubSystem($logDir."MATE.sh",$mateCmd,1,"20G","_MT$JNUM",$jobN,"",1,\@General_Hosts,\%QSBopt) ;
		#### 3 : if mate pairs, process these now (and remove corresponding raw fiiles
	}
	foreach my $hrr (@matePrps){
		my %nateFiles = %{$hrr};
		push(@pa1,$nateFiles{pe1});push(@pa2,$nateFiles{pe2});push(@pas,$nateFiles{se}); push(@libInfo,"pe4mt$ii");
		push(@pa1,$nateFiles{mp1});push(@pa2,$nateFiles{mp2});push(@libInfo,"mate$ii");
		push(@pa1,$nateFiles{un1});push(@pa2,$nateFiles{un2});push(@libInfo,"mate_unkn$ii");
	}
#die "@pa1\n@libInfo\n";
	
	#if (!$calcUnzp ){ return ($jobN,\@pa1,\@pa2, \@pas, $WT, $rawReads, $mmpu,\@libInfo, $jobNUZ);}

#mmpu number of EMBL
	return ($jobN,\@pa1,\@pa2, \@pas, $WT, $rawReads, $mmpu,\@libInfo, $jobNUZ);
}


sub prepMOTU2(){
	my $orimotu2 = getProgPaths("motu2_dir");
	my $m2sub="";
	if ($orimotu2 =~ m/\/([^\/]+)\/?$/){
		$m2sub = $1;
	} elsif (! -d $orimotu2) {
		die "$orimotu2 seems not to be a dir\n";
	}
	my $m2Glb = $runTmpDirGlobal."DB/";
	my $m2Bin = "python $m2Glb/$m2sub/motus";
	my $cmd = "";
	#print "$m2Glb/$m2sub && !-e $m2Glb/$m2sub/motu2";
	if (!-d "$m2Glb/$m2sub" && !-e "$m2Glb/$m2sub/motu2"){
		$cmd .= "cp -r $orimotu2 $m2Glb\n";
	}
	#die $cmd;
	my $tmpCmd=""; my $jobN="";
	if ($cmd ne ""){
		$jobN= "_m2DB";
		($jobN, $tmpCmd) = qsubSystem("$baseOut/LOGandSUB/motu2DB.sh",$cmd,1,"1G",$jobN,"","",1,\@General_Hosts,\%QSBopt) ;
	}
	
	return ($jobN,$m2Bin);
}
sub prepKraken(){
	#my ($DBdir) = @_;
	#my $oriKrakDir = "/g/scb/bork/hildebra/DB/kraken/";
	my $oriKrakDir = getProgPaths("Kraken_path_DB");
	my %DBname;
	$DBname{"hum1stTry"} = 1 if ($humanFilter);
	$DBname{"minikraken_2015"} = 1 if ($DO_EUK_GENE_PRED);
	$DBname{$globalKraTaxkDB} = 1 if ($globalKraTaxkDB ne "");
	my $cmd = "";my $jobN= "";
	#die "krakper\n";
	foreach my $kk (keys %DBname ){
		if (!-d "$oriKrakDir$kk"){die "can't find kraken db $oriKrakDir$kk\n";}
		if (!-d "$krakenDBDirGlobal/$kk" && !-e "$krakenDBDirGlobal/$kk/cpFin.stone" ){
			$cmd =  "cp -r $oriKrakDir$kk $krakenDBDirGlobal/\n";
			$cmd .= "touch $krakenDBDirGlobal/$kk/cpFin.stone\n";
		}
	}
	my $tmpCmd="";
	if ($cmd ne ""){
		$jobN= "_KRDB";
		($jobN, $tmpCmd) = qsubSystem("$baseOut/LOGandSUB/krkDB.sh",$cmd,1,"1G",$jobN,"","",1,\@General_Hosts,\%QSBopt) ;
		#print "Fix KRDB 2416\n";
	}
	#die $cmd;
	return $jobN;
}

sub krakHSap($ $ $ $ $ $){
	my ($ar1, $ar2, $ars,$tmpD,$jDep,$checkIfExists) = @_;
	my @pa1 = @{$ar1}; my @pa2 = @{$ar2}; my @pas = @{$ars};
	return $jDep unless ($humanFilter);
	my $outputExists=1;
	for (my $i=0;$i<@pa1;$i++){
		$outputExists=0 if (!-e $pa1[$i] || !-e $pa2[$i]);
	}
	for (my $i=0;$i<@pas;$i++){
		$outputExists=0 if (!-e $pas[$i] );
	}
	return $jDep if ($outputExists && $checkIfExists);
	
	#my ($DBdir,$DBname) = @_;
	my $DBdir = $krakenDBDirGlobal;
	my $unsplBin = getProgPaths("unsplitKrak_scr");#"perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/unsplit_krak.pl ";
	my $DBname = "hum1stTry"; my $numThr = 6;
	my $cmd = "\n\nmkdir -p $tmpD\n\n"; my $tmpF ="$tmpD/krak.tmp.fq";
	my $fileDir = "";
	for (my $i=0;$i<@pa1;$i++){
		my $r1 = $pa1[$i]; my $r2 = $pa2[$i];
		$pa1[$i] =~ m/(.*\/)[^\/]+$/; $fileDir= $1 if ($fileDir eq "");
		my $gzFlag = "";$gzFlag =  "--gzip-compressed" if ($pa1[$i] =~ m/\.gz$/);
		$cmd .= "$krkBin --paired --preload --threads $numThr  $gzFlag --fastq-input --unclassified-out $tmpF --db $DBdir/$DBname  $r1 $r2 > /dev/null\n";
		#overwrites input files
		$r1 =~ s/\.gz$//; $r2 =~ s/\.gz$//;
		$cmd .= "$unsplBin $tmpF $r1 $r2\n";
		if ($gzFlag ne ""){
			$cmd .= "$pigzBin -p $numThr $r1 $r2\n";
		}
	}
	$cmd .= "\n\nrm -f $fileDir/krak.stone\n\n";
	for (my $i=0;$i<@pas;$i++){
		my $rs = $pas[$i]; 
		my $gzFlag = "";$gzFlag =  "--gzip-compressed" if ($pas[$i] =~ m/\.gz$/);
		$cmd .= "$krkBin --preload --threads $numThr --fastq-input $gzFlag --unclassified-out $tmpF --db $DBdir/$DBname  $rs > /dev/null\n";
		if ($gzFlag eq ""){
			$cmd .= "rm -f $rs; mv $tmpF $rs\n";
		} else{
			$cmd .= "rm -f $rs; $pigzBin -p $numThr -c $tmpF > $rs\nrm $tmpF\n";
		}
		#overwrites input files
	}
	$cmd .= "\n\n";
	$cmd .= "touch $fileDir/krak.stone\n";
	my $jobN = ""; my $tmpCmd="";
	unless (-e "$fileDir/krak.stone"){
		#die "$fileDir\n";
		$jobN = "_KR$JNUM";
		($jobN, $tmpCmd) = qsubSystem($logDir."KrakHS.sh",$cmd,$numThr,"16G",$jobN,$jDep.";$krakDeps","",1,\@General_Hosts,\%QSBopt) ;
	}
	return $jobN;
}

sub genoSize(){
	my ($arp1,$arp2,$ars,$mergRdsHr,$oD,$jdep) = @_;
	my @pa1 = @{$arp1}; my @pa2 = @{$arp2}; my @pas = @{$ars};
	my $cmd = "mkdir -p $oD\n";
	my $microCensBin = getProgPaths("microCens");
	for (my $i=0;$i<@pa1;$i++){
		$cmd .= "$microCensBin -t 2 $pa1[$i],$pa2[$i] $oD/MC.$i.result\n";
	}
#	die $cmd;
	my $jobName = "_GS$JNUM"; my $tmpCmd;
	
	($jobName,$tmpCmd) = qsubSystem($logDir."MicroCens.sh",$cmd,2,"40G",$jobName,$jdep,"",1,\@General_Hosts,\%QSBopt);
	return $jobName;
}
sub krakenTaxEst(){
	my ($arp1,$arp2, $ars, $outD, $tmpD,$name,$jobd) = @_;
	my @pa1 = @{$arp1}; my @pa2 = @{$arp2}; my @pas = @{$ars};
	#$outD.= "$globalKraTaxkDB/";
	my $krakStone = "$outD/krakDone.sto";
	return $jobd if (-d $outD && -e $krakStone);
	my $numCore = $krakenCores;
	my @thrs = (0.01,0.02,0.04,0.06,0.1,0.2,0.3);
	my $cmd = "mkdir -p $outD\nrm -rf $tmpD\nmkdir -p $tmpD\n";
	my $it =0;
	my $curDB = "$krakenDBDirGlobal/$globalKraTaxkDB";
	#die $curDB."\n";
	#paired read tax assign
	for (my $i=0;$i<@pa1;$i++){
		my $r1 = $pa1[$i]; my $r2 = $pa2[$i];
		$pa1[$i] =~ m/(.*\/)[^\/]+$/; 
		$cmd .= "$krkBin --paired --preload --threads $numCore --fastq-input  --db $curDB  $r1 $r2 >$tmpD/rawKrak.$it.out\n";
		for (my $j=0;$j< @thrs;$j++){
			$cmd .= "$krkBin-filter --db $curDB  --threshold $thrs[$j] $tmpD/rawKrak.$it.out | $krkBin-translate --mpa-format --db $curDB > $tmpD/krak_$thrs[$j]"."_$it.out\n";
		}
		#$cmd .= " $krakCnts1 $tmpD/krak$it.out $tmpD/krak$it.tax\n";
		$it++;
	}
	$cmd .= "\n\n";
	#single read tax assign
	for (my $i=0;$i<@pas;$i++){
		my $rs = $pas[$i]; 
		$cmd .= "$krkBin --preload --threads $numCore --fastq-input  --db $curDB  $rs >$tmpD/rawKrak.$it.out\n";
		#$cmd .= " | tee ";#$krkBin-filter --db $curDB  --threshold 0.01 | $krkBin-translate --mpa-format --db $curDB > $tmpD/krak$it.out\n";
		for (my $j=0;$j< @thrs;$j++){
			$cmd .= "$krkBin-filter --db $curDB  --threshold $thrs[$j] $tmpD/rawKrak.$it.out | $krkBin-translate --mpa-format --db $curDB > $tmpD/krak_$thrs[$j]"."_$it.out\n";
		}
		#overwrites input files
		$it++;
	}
	
	#TODO: 1: make table; 2: copy to outD
	$cmd .= "\n\n";
	for (my $j=0;$j< @thrs;$j++){
		$cmd .= "cat $tmpD/krak_$thrs[$j]"."_*.out > $tmpD/allkrak$thrs[$j].out\n";
		$cmd .= "$krakCnts1 $tmpD/allkrak$thrs[$j].out $outD/krak.$thrs[$j].cnt.tax\n";
	}

	$cmd .= "touch $krakStone\n";
	$cmd .= "rm -r $tmpD";

	my $jobName = "_KT$JNUM"; my $tmpCmd;
	if (!-d $outD || !-e $krakStone){
		($jobName,$tmpCmd) = qsubSystem($logDir."KrkTax.sh",$cmd,$numCore,"20G",$jobName,$jobd.";$krakDeps","",1,\@General_Hosts,\%QSBopt);
	}
	return $jobName;
}



sub bam2cram($ $ $ $ $ $ $){#save further space: convert the bam to cram
	my ($nxtBAM,$REF,$del,$subm,$doCram, $stone, $numCore) = @_;
	my $ret = "";
	my $nxtCRAM = $nxtBAM;	
	#my $numCore = 4;
	if (!$doCram){return ($ret,"");}
	$nxtCRAM =~ s/\.bam$/\.cram/;
	if (!-e $nxtBAM && -e $nxtCRAM){print "CRAM exists, but no stone set\n"; system "rm $nxtCRAM";return $ret;}
	#my $stone = $nxtBAM;	$stone =~ s/\.bam$/\.cram\.sto/;
	$ret.="rm -f $nxtCRAM\n" if (-e $nxtCRAM);
	$ret.="$smtBin view -@ $numCore -T $REF -C -o $nxtCRAM $nxtBAM\n";
	#$ret.="$sambambaBin view -T $REF -t $numCore -f cram -o $nxtCRAM $nxtBAM\n";
	$ret.="rm -f $nxtBAM\n" if ($del);
	$ret .= "touch $stone\n";
	#die $ret;
	if ($subm){
		my $jobN = "_CRAM$JNUM"; my $tmpCmd;
		($jobN, $tmpCmd) = qsubSystem($logDir."BAM2CRAMxtra.sh",$ret,$numCore,"5G",$jobN,"","",1,[],\%QSBopt);
	}
	return ($ret,$nxtCRAM);
}

sub jgi_depth_cmd_depr($){
	my ($nxtBAM) = @_;
	my $covCmd = "";
	$covCmd .= "\n$jgiDepthBin";
	$covCmd .= " --outputDepth $nxtBAM.jgi.depth.txt  --percentIdentity 97 --pairedContigs $nxtBAM.jgi.pairs.sparse $nxtBAM > $nxtBAM.jgi.cov\n";
	$covCmd .= "\n$pigzBin -p 4 $nxtBAM.jgi.*\n\n";
	if (-e "$nxtBAM.jgi.cov"){$covCmd="";}
	#$covCmd .= "gzip $nxtBAM.jgi*\n";
	return $covCmd;
}

sub check_map_done{
	my ($doCram, $finalD, $baseN, $mappDir) = @_;
	
	#my $aa = (stat "$finalD/$baseN-smd.bam")[7];
	#die "$finalD/$baseN-smd.bam "."$aa\n";


	if ($doCram && (-e "$finalD/$baseN-smd.cram.sto" && -s "$finalD/$baseN-smd.bam.coverage.gz"  ) ){#&& !$params{bamIsNew} ) ){
		return (1);
	} elsif (!$doCram && -e "$finalD/$baseN-smd.bam" && -s "$finalD/$baseN-smd.bam.coverage.gz" ){#&& !$params{bamIsNew}){
		return (1);
	}
	
	if ( -e "$mappDir/$baseN-smd.bam.coverage.gz" && (-e "$mappDir/$baseN-smd.bam" || -e "$mappDir/$baseN-smd.cram") ){# && !$params{bamIsNew}){ #already stored in mapping dir, still needs to be copied
		#die "$mappDir/$baseN-smd.bam.coverage.gz";
		return (2);
	}
	return 0;
}


sub mapReadsToRef{
	my ($dirsHr,$outName, $is2ndMap, $par1,$par2, $parS, $Ncore,#hm,m,x,x,x,x,x
		$REF,$jDepe, $unaligned,$immediateSubm,#m,x,x,x
		$doCram,$smpl,$libAR) = @_;#x,x,x
	#die "$REF\n";
			# ($dirsHr,$outName, $is2ndMap, $par1,$par2,$Ncore,#hm,m,x,x,x,x,x
	#	$REF,$jDepe, $unaligned,$immediateSubm,#m,x,x,x,m
	#	$doCram,$smpl,$libAR) = @_;#x,x,x
		#get essential dirs...
	my $mappDirPre = ${$dirsHr}{glbMapDir};	my $nodeTmp = ${$dirsHr}{nodeTmp}; #m,s
	$nodeTmp.="_map/";

	my $tmpOut = ${$dirsHr}{glbTmp};	my $finalD = ${$dirsHr}{outDir}; #s,m
	#die "$finalD\n";
	my @finalDS = split /,/,$finalD;
	my @mappDir = split /,/,$mappDirPre;

	#my $bwtIdx = $REF.".bw2";
	my @bwtIdxs;
	my @libsOri = @{$libAR};
	#already exists
	#print "IS${unaligned}SI\n";
	my $baseN = $smpl;#$RNAME."_".$QNAME;
	
	my $bashN = "";	if ($is2ndMap){$bashN = "$outName"; $bashN =~ s/,/./g; if (length($bashN)>50){$bashN=substr($bashN,0,40)."_etc";}}
	my @outNms = split /,/,$outName;
	if ($outName ne "" ){
		$baseN = $outNms[0];
	} else {
		@outNms = ($baseN);
	}
	my @tmpOut22 = ($tmpOut."/$baseN.iniAlignment.bam");
	#global value overwrites local value
	if ($doCram){$doCram = $doBam2Cram;}
	my @pa1 = @{$par1}; my @pa2 = @{$par2}; my @paS = @{$parS};
	
	
	my %params;
	my $bamFresh = 0; #is the bam newly being created?
	my $decoyModeActive=0; #decoy mapping
	my $map2ndTogether = $mapModeTogether; #map competetively among all reference genomes provided might change mapping result, if other genome set is used)
	$decoyModeActive=1 if ( $mapModeDecoyDo && exists($make2ndMapDecoy{Lib}) && -e $make2ndMapDecoy{Lib});
	my $isSorted = 0;		$isSorted=1 if (@pa1==1 && $mapModeDecoyDo && $decoyModeActive);
	if (!$decoyModeActive){
		@bwtIdxs = split /,/,$REF;
		for (my $kk=0;$kk<@bwtIdxs;$kk++){
			$bwtIdxs[$kk] .= ".bw2";
		}
	}
	#die "$isSorted\n";
	$params{sortedbam}=$isSorted; $params{bamIsNew} = $bamFresh; $params{is2ndMap} = $is2ndMap;
	$params{immediateSubm} =  $immediateSubm;;

	my $outputExistsNEx = 0;
	for (my $k=0;$k<@outNms;$k++){
		$tmpOut22[$k] = $tmpOut."/$outNms[$k].iniAlignment.bam"; 
	}
	for (my $k=0;$k<@outNms;$k++){
		#print "$tmpOut22\n";
		if ($rewrite2ndMap){$outputExistsNEx++; system "rm -fr $tmpOut22[$k] $finalDS[$k]/$outNms[$k]-smd* $mappDir[$k]/$outNms[$k]-smd*"; next;}
		my $outstat = check_map_done($doCram, $finalDS[$k], $outNms[$k], $mappDir[$k]);

		next if ($outstat);#-e "$finalDS[$k]/$outNms[$k]-smd.bam.coverage.gz" );#|| -e "$mappDir[$k]/$outNms[$k]-smd.bam.coverage.gz");
		#print "-e $finalDS[$k]/$outNms[$k]-smd.bam.coverage.gz || -e $mappDir/$outNms[$k]-smd.bam.coverage.gz";
		if (-e $tmpOut22[$k] && -s $tmpOut22[$k] < 100){unlink $tmpOut22[$k];}
		if (!-e $tmpOut22[$k]){ $outputExistsNEx++; }
	}
	#die "@outNms \n$outputExistsNEx\n";
	if ($outputExistsNEx == 0){
		return ("","",\%params);
	} 
	
	my $NcoreL = int($Ncore);#correction for threads
	my $nxtCRAM = "$tmpOut/$baseN-smd.cram";
	my $tmpOut21 = $nodeTmp."/$baseN.iniAlignment.bam";
	my $sortTMP = $nodeTmp."/$baseN.srt";
	#print "$nxtBAM\n";
	#die("too far\n");
	
	my $retCmds="";my $tmpCmd=""; my $xtraSamSteps1="";
	#my $nxtCRAM = "$mappDir/$baseN-smd.cram";

	system("mkdir -p ".join(" ",@mappDir)." " .join(" ",split(/,/,$tmpOut)));
	#move ref DB & unzip
	#system("rm -r $tmpOut\n mkdir -p $tmpOut\n cp $REF $tmpOut");
	#$REF = $tmpOut.basename($REF);
	my $unzipcmd = "";
	if ($REF =~ m/\.gz$/){$unzipcmd .= "gunzip $REF\n";$REF =~ s/\.gz$//;}
	my $jobN = "";
	my $tmpUna = $tmpOut."/unalTMP/";
	#Error: No EOF block on /g/scb/bork/hildebra/SNP/MeHiAss/MH0411//tmp//mapping/Alignment.bam, possibly truncated file.
	if (0&& -e $logDir.$bashN."bwtMap2.sh.etxt"){open I,"<$logDir/".$bashN."bwtMap2.sh.etxt" or die "Can't open old bowtie_2 logfile $logDir\n"; my $str = join("", <I>); close I;
		if ($str =~ /Error: No EOF block on (.*), possibly truncated file\./){system("rm $1 ".join (" ",@tmpOut22) );}	
		close I;	
	}
	#depending on setup, mappDir == tmpOut
	my $algCmd = "rm -rf $tmpOut $nodeTmp\nmkdir -p $tmpOut $nodeTmp\n"; 
	#die "$algCmd\n@mappDir\n";
	#my $algCmd = "rm -rf ".join(" ",split(/,/,$mappDir))."\nmkdir -p ".join(" ",split(/,/,$mappDir))." $tmpOut $nodeTmp\n"; 
	$algCmd .= "mkdir -p $logDir/mapStats/\n";
	my $statsF = $logDir."mapStats/".$bashN."mapStats.txt";
	
	my @regs;#subset of DB seqs to filter for 
	my @reg_lcs;
	$REF =~ m/([^\/]+)$/; my $REFnm = $1; $REFnm =~ s/\.f.*a$//; 
	#die "$REF\n$REFnm\n";
	if ($decoyModeActive || $map2ndTogether){
		#first create a new ref DB, including the targets and the assemblies from this dir
		my $bwtIdx = "$nodeTmp/$REFnm.decoyDB.fna";
		if ($map2ndTogether){
			$bwtIdx = "$map2ndTogRefDB{DB}";
		} else {
			$algCmd.= "\n$decoyDBscr $REF $make2ndMapDecoy{Lib} $bwtIdx $NcoreL $outName $finalD\n";
		}
		#die "$algCmd\n";
		$bwtIdx .= ".bw2";
		
		$xtraSamSteps1 = "$smtBin sort -@ $NcoreL -T $sortTMP - |";
		@regs = @{$make2ndMapDecoy{regions}};
		@reg_lcs =  @{$make2ndMapDecoy{region_lcs}};
		#for (my $k=0;$k<@regs;$k++){
		#die "$bwtIdx\n$algCmd\n";
		@bwtIdxs = ($bwtIdx);
	} 
	#die "@bwtIdxs\n";
	
	my $cntAli=0;
	my $numLib = scalar @pa1 + scalar @paS; 
	my $anyUsedPairs= scalar @pa1 > 0;
#	if ($numLib==0){
#		$numLib = scalar @paS; 
#	}
	#die "@bwtIdxs\n"; 
	for (my $kk=0;$kk<@bwtIdxs;$kk++){  #iterator over different genomes
		#die  "$finalDS[$kk]/$outNms[$kk]-smd.bam\nXXX\n$mappDir[$kk]\n";
		if ($decoyModeActive || $map2ndTogether){
			my $allDone=1;
			for (my $k=0;$k<@outNms;$k++){
				#print "$finalDS[$k] $outNms[$k] $mappDir[$k]\n";
				$allDone =0 unless(check_map_done($doCram, $finalDS[$k], $outNms[$k], $mappDir[$kk]));
			}
			#die;
			last if ($allDone);
		} elsif (-e $tmpOut22[$kk] || check_map_done($doCram, $finalDS[$kk], $outNms[$kk], $mappDir[$kk])){ #this check is for non-decoy mode
			#(-e "$finalDS[$kk]/$outNms[$kk]-smd.bam" && -e "$finalDS[$kk]/$outNms[$kk]-smd.bam.coverage.gz") ){
			next;
		} #|| -e "$mappDir[$kk]/$outNms[$kk]-smd.bam.coverage.gz"
		$cntAli++;
		$bamFresh=1;
		#print "ali\n";
		$algCmd .= "rm -rf $mappDir[$kk]\nmkdir -p $mappDir[$kk]\n"; 

		my @subBams; 
		my $algCmdBase = "$bwt2Bin --no-unal --end-to-end -p $NcoreL -x $bwtIdxs[$kk] ";
		if ($unaligned ne ""){
			#die "IS${unaligned}SI\n";
			#system "mkdir -p $unaligned $tmpUna\n";
			$algCmd .= "mkdir -p $unaligned $tmpUna\n\n";
			$algCmdBase .= " --un-conc $tmpUna ";
		}
		if ($MapperProg==2){
			$algCmdBase = "$bwaBin mem -t $NcoreL ";
		}
		#--al-conc #prints pairs that hit
		#my $tmpOut22 = $tmpOut."ali.2.sam";
		
		#join(",",@pa2)
		#die "$numLib\n$usePairs\n";
		for (my $i=0; $i< $numLib; $i++){
			my $usePairs=1;
			if ($i >= scalar @pa1){$usePairs=0;}
			my $iS = $i - scalar @pa1;
			#$pa1[$i] =~ m/\/([^\/]+)\.f.*q$/;
			if ($MapperProg==1){
				my $rgID = "$smpl"; my $rgStr = "--rg SM:$smpl --rg PL:ILLUMINA "; #PU:lib1
				if ($usePairs){
					$rgStr .= "--rg LB:$libsOri[$i] ";
					$rgStr .= " -X $mateInsertLength " if ($libsOri[$i] =~ m/mate/);
				} else {
					$rgStr .= "--rg LB:$libsOri[$iS] ";
					$rgStr .= " -X $mateInsertLength " if ($libsOri[$iS] =~ m/mate/);
				}
				if ($usePairs){
					$algCmd .= "$algCmdBase -1 ".$pa1[$i]." -2 ".$pa2[$i];
				} else {
					$algCmd .="$algCmdBase -U ".$paS[$iS];
				}
				$algCmd .= " --rg-id $rgID $rgStr ";
			} elsif ($MapperProg==2){
				my $rgID = "$smpl"; my $rgStr = "'\@RG\\tID:$1\\tSM:$smpl\\tPL:ILLUMINA";
				$rgStr .= "\\tLB:lib1'";
				die "single end mapping not implemented for bwa\n" if (!$usePairs);
				$algCmd .= $algCmdBase." -R $rgStr $REF " .$pa1[$i]." ".$pa2[$i];#| $smtBin view -@ $NcoreL -b - > $tmpOut21.$i\n  $smtBin flagstat $tmpOut21.$i > $statsF.$i \n";
			}
			my $iTO = "$tmpOut21.$i.$kk";
			$algCmd .= "| $xtraSamSteps1  $smtBin view -b1 -@ $NcoreL -F 4 - > $iTO\n";
			
			if ($decoyModeActive || $map2ndTogether){#remove unnecessary reads & filter specific reads for each ref genome into separate bam
				$algCmd .= "$smtBin index $iTO\n";
				#die;
				for (my $k=0;$k<@regs;$k++){
					#		print "$k\t$finalDS[$k]\n";
					if(check_map_done($doCram, $finalDS[$k], $outNms[$k], $mappDir[$k])){$subBams[$k]="";next;}

					$algCmd .= "$bamHdFilt_scr $iTO $reg_lcs[$k] 0 > $iTO.decoy.sam.$k\n";
					$algCmd.= "  $smtBin view -@ $NcoreL $iTO $regs[$k] >> $iTO.decoy.sam.$k\n";
					$algCmd.= "  $smtBin view -b -h -@ $NcoreL $iTO.decoy.sam.$k > $iTO.decoy.$k\nrm $iTO.decoy.sam.$k \n";
					$subBams[$k] .= " $iTO.decoy.$k";  
				}
				
				$algCmd.= "rm $iTO\n";# mv $tmpOut21.decoy.$i $tmpOut21.$i\n";
			} else {
				$subBams[0] .= " $iTO"; 
			}

			#| $smtBin view -1 - |tee > $tmpOut21.$i  |  $smtBin flagstat - > $statsF.$i \n\n";
			
		}
		#die "@tmpOut22\n@subBams\n";
		for (my $k=0;$k<@subBams;$k++){
			#$tmpOut22 = $tmpOut."/$outNms[$k].iniAlignment.bam";
			#print $tmpOut22."\n";
			#if (-e $tmpOut22){ next;}
			my $tarBam = $tmpOut22[$kk];
			$tarBam = $tmpOut22[$k] if ($decoyModeActive || $map2ndTogether);
			next if ($subBams[$k] eq "");#case that decoy map has already created parts of the mappings..
			if ($numLib > 1){
				$algCmd .= "\n$smtBin cat ".$subBams[$k]." > $tarBam\n"; #$k here, because this refers to @regs
				$algCmd .= "\nrm ".$subBams[$k]."\n";
			} else { #nothing else, compression is now in the bowtie2 phase
				#$algCmd .= "\n$smtBin view -bS -F 4 -@ $Ncore $subBams[0] > $tmpOut22\n";
				
				$algCmd .=  "\nmv $subBams[$k] $tarBam\n"; #kk here, because this is the alignment to each single bwtIdx
			}
		}

	}
	#die "$algCmd\n";
	my $mapProgNm = "";
	if ($MapperProg==1){
		$mapProgNm = "bowtie2";
	}elsif ($MapperProg==2){
		$mapProgNm = "bwa";
	}
	foreach my $mpdSS (@mappDir) {
		if (!-e "$mpdSS/map.sto"){$bamFresh=1;}
		#$algCmd .= "echo '$mapProgNm' > $mpdSS/map.sto\n"; 
	}

	#system($algCmd." -U $p2 -S $tmpOut22\n");
	#die();
	
	my $nodeCln = "\nrm -rf $nodeTmp\n";
	my $unalignCmd = "";
	if ($unaligned ne "" && $MapperProg == 1 && !-e "$unaligned/unal.1.fq.gz"){
		$unalignCmd .= "mkdir -p $unaligned\n";
		$unalignCmd .= "$pigzBin -p $NcoreL -c $tmpUna/un-conc-mate.1 > $unaligned/unal.1.fq.gz;\n$pigzBin -p $NcoreL -c $tmpUna/un-conc-mate.2 > $unaligned/unal.2.fq.gz\n";
		$unalignCmd .= "rm -f $tmpUna/un-conc-mate.*\n";
	}
	print "$cntAli new alignments\n" if ($cntAli > 0);
	
	if ( $bamFresh  ){
		#die "$unzipcmd.$algCmd.$nodeCln";
		$jobN = "_BT$JNUM$outNms[0]"; $bamFresh = 1; 
		($jobN,$tmpCmd) = qsubSystem($logDir.$bashN."bwtMap.sh",
				$unzipcmd.$algCmd.$unalignCmd.$nodeCln,
				$Ncore,$MappingMem,$jobN,$jDepe,"",$immediateSubm,\@General_Hosts,\%QSBopt) ;
		$retCmds .= $tmpCmd;
	}
	#die "TOOfar\n";
	#xtraSamSteps1 = isSorted
	$params{sortedbam}=$isSorted; $params{bamIsNew} = $bamFresh; $params{is2ndMap} = $is2ndMap;
	$params{immediateSubm} = $immediateSubm; $params{usePairs} = $anyUsedPairs;
	#die "$jobN\n$immediateSubm\n";
	return($jobN,$retCmds,\%params);
}	
	
sub bamDepth{
	my ($dirsHr,  #   $mappDir,$tmpOut,$nodeTmp,$finalD,#dirs to work in
			$outName,$REF,$jDep,$doCram,$mapparhr) = @_;
	#die "bamdep\n";
	my %params = %{$mapparhr};
	my ($isSorted , $bamFresh,$is2ndMap, $usePairs) =($params{sortedbam},$params{bamIsNew},$params{is2ndMap},$params{usePairs});
	#recreate base pars from map2tar sub
	my $locDoRmDup = $doRmDup;
	$locDoRmDup = 0 if (!$usePairs);
	my $immediateSubm = $params{immediateSubm} ;
	my $mappDir = ${$dirsHr}{glbMapDir};	my $nodeTmp = ${$dirsHr}{nodeTmp}."_bamDep/$outName/";
	my $tmpOut = ${$dirsHr}{glbTmp};	my $finalD = ${$dirsHr}{outDir};

	my $baseN = $outName;
	my $bashN = "";	if ($is2ndMap){$bashN = "$outName"; $bashN =~ s/,/./;}
	my $tmpOut22 = $tmpOut."/$baseN.iniAlignment.bam";
	my $cramSTO = "$mappDir/$baseN-smd.cram.sto";
	my $nxtBAM = "$tmpOut/$baseN-smd.bam";
	my $sortTMP = $nodeTmp."/$baseN.srt";
	my $sortTMP2 = $nodeTmp."/$baseN.2.srt";
 
	#check if already done
	my $outstat = check_map_done($doCram, $finalD, $baseN, $mappDir);
	#die "$outstat";
	if ($outstat>=1){return ("","",$outstat);}
	#die "$mappDir/$baseN-smd.bam.coverage.gz\n$finalD/$baseN-smd.bam.coverage.gz\n" ;#if (-e "$finalD/$baseN-smd.bam.coverage.gz");
	
	
	
	my $numCore = 6;#new functionality with sambamba
	#my $biobambamBin = "bamsormadup";
	#depth profile
	#my $cmd = "$smtBin faidx $REF\n $smtBin view -btS $REF.fai $tmpOut/$baseN.sam > $tmpOut/$baseN.bam\n";
	my $cmd = "sleep 2\n";
	#$cmd .= "mkdir -p $nodeTmp\n";
	$cmd .= "mkdir -p $mappDir $tmpOut $nodeTmp\n";
	#sort & remove duplicates
	if (1 || -z $nxtBAM){
		#$cmd .= "$sambambaBin sort -t $numCore -o $tmpOut2s $tmpOut22 \n$sambambaBin markdup -r -t $numCore $tmpOut2s $nxtBAM\n";
		#$cmd .= "$biobambamBin sort -t $numCore $tmpOut22 /dev/stdout | $sambambaBin markdup -r -t $numCore /dev/stdin $nxtBAM\n";
		#$cmd .= "$novosrtBin --removeDuplicates --ram 100G -o $nxtBAM -i $tmpOut22 \n\n";
		#$cmd .= "/g/bork3/home/hildebra/bin/htsbox/./htsbox pileup -f $REF -Q20 -q30 -Fs3 sorted.bam > $REF.cns\n" if ($map_DoConsensus);
		
		if ($locDoRmDup){
		#bit complicated in samtools now: first sort by name, then fixmate (samtools 1.8)
			$cmd .= "$smtBin sort -n -m 20G -T $sortTMP -@ $numCore $tmpOut22 | $smtBin fixmate -m -@ $numCore - - | $smtBin sort -T $sortTMP2 -m 20G -@ $numCore - | $smtBin markdup -s -r -@ $numCore - $nxtBAM\n";
			#if ($isSorted  ){#no sort required
			#	#$cmd .= "$smtBin rmdup -s $tmpOut22 $nxtBAM;\n"; #-s 
			#	$cmd .= "$smtBin $tmpOut22 - | $smtBin markdup -r -@ $numCore - $nxtBAM;\n"; #-s 
			#} else {
			#	$cmd .= "$smtBin sort -@ $numCore -m 2G -T $sortTMP $tmpOut22 | $smtBin markdup -r -@ $numCore  - $nxtBAM\n";#$smtBin rmdup -s - $nxtBAM;\n";#-s 
			#}
			#$cmd .= "$smtBin sort -@ $numCore $tmpOut22  | $sambambaBin markdup -r -t $numCore /dev/stdin $nxtBAM\n";
			#die "$cmd\n";
		} else {
			if ($isSorted ){
				$cmd .= "mv $tmpOut22 $nxtBAM\n";
			} else {
				$cmd .= "$smtBin sort -@ $numCore -m 50G -T $sortTMP $tmpOut22  > $nxtBAM\n";
			}
		}
		$cmd .= "$smtBin index -@ $numCore $nxtBAM\n";
		$cmd .= "rm -f $tmpOut22 \n" if (!$isSorted);
	}
	#$cmd .= "$smtBin view -bS $tmpOut21 > $tmpOut/$baseN.bam\n";
	#my $mdJar = "/g/bork5/hildebra/bin/picard-tools-1.119/MarkDuplicates.jar";
	#$cmd .= "java -Xms1g -Xmx24g -XX:ParallelGCThreads=2 -XX:MaxPermSize=1g -XX:+CMSClassUnloadingEnabled ";		$cmd .= "-jar $mdJar INPUT=$mappDir/$baseN-s.bam OUTPUT=$mappDir/$baseN-smd.bam METRICS_FILE=$mappDir/$baseN-smd.metrics ";		
	#$cmd .= "AS=TRUE VALIDATION_STRINGENCY=LENIENT MAX_FILE_HANDLES_FOR_READ_ENDS_MAP=1000 REMOVE_DUPLICATES=TRUE\n\n";
	
	#$cmd .= "$smtBin index $nxtBAM\n";#$mappDir/$baseN-smd.bam\n";
	#takes too much space, calc on the fly!
	#$cmd .= "$smtBin depth $mappDir/$baseN-s.bam > $mappDir/$baseN.depth.bam.txt\n";#depth file (different estimator)
	my $covCmd = "";
	if (!-e "$nxtBAM.coverage.gz"){
		
		$covCmd = "$bedCovBin -ibam $nxtBAM -bg > $nxtBAM.coverage\n";
		$covCmd .= "rm -f $nxtBAM.coverage.gz\n$pigzBin -p $numCore $nxtBAM.coverage\n";
	}
	#die "$covCmd\n";
	
	#jgi depth profile - not required, different call to metabat
	$covCmd .= jgi_depth_cmd($nxtBAM,$nxtBAM,95) if ($DoJGIcoverage);
	#$covCmd .= "/g/bork5/hildebra/bin/bedtools2-2.21.0/bin/genomeCoverageBed -ibam $nxtBAM -bg  | ".'awk \'BEGIN {pc=""} {	c=$1;	if (c == pc) {		cov=cov+$2*$5;	} else {		print pc,cov;		cov=$2*$5;	pc=c}';
	#$covCmd .= "} END {print pc,cov}\' $nxtBAM.coverage | tail -n +2 > $nxtBAM.coverage.percontig";
	
	my ($CRAMcmd,$CRAMf) = bam2cram($nxtBAM,$REF,1,0,$doCram,$cramSTO, $numCore);
	$CRAMcmd .= "\nmv $nxtBAM* $CRAMf $mappDir\n" unless ($mappDir eq $tmpOut);
	$CRAMcmd .= "echo \"".basename($nxtBAM)."\" > $mappDir/done.sto\n";


	my $newJobN = "_SBAM$JNUM$outName";	
	#subsequent jobs not dependent on this one
	my $jobN2 = $jDep; my $retCmds="";
	$covCmd = "" if ( -s "$nxtBAM.coverage");
	
	#my $cleaner = "mv $tmpD $fin
	if (0){
		print "B1 " if ( $doCram && !-e $cramSTO); print "B2 " if (  !-s "$nxtBAM.coverage"); print "B3 " if ( $bamFresh);
		print " ".$cramSTO."\n";
	}
	my $nodeCln = "\nrm -rf $nodeTmp\n";
	#die "($doCram && !-e $cramSTO) || ( !-s $nxtBAM.coverage) || $bamFresh\n";
	if ( ($doCram && !-e $cramSTO) || ( !-s "$nxtBAM.coverage.gz") ){#|| $bamFresh){
		($jobN2,$retCmds) = qsubSystem($logDir.$bashN."bwtMap2.sh",
				$cmd."\n".$covCmd."\n".$CRAMcmd."\n$nodeCln\n"#.$covCmd2
				,$numCore,int(60/$numCore)."G",$newJobN,$jDep,"",$immediateSubm,\@General_Hosts,\%QSBopt);
	}

	#die();
	return($jobN2,$retCmds,$outstat);
}

sub metphlanMapping{
	my ($inF1a,$inF2a,$tmpD,$finOutD,$smp,$Ncore,$deps) = @_;
	my $stone = $finOutD."$smp.MP2.sto";
	if (!$DoMetaPhlan ||  -e $stone){return;}
	my @car1 = @{$inF1a}; my @car2 = @{$inF2a};
	my $inF1 = join(",",@car1); my $inF2 = join(",",@car2); 
	system "mkdir -p $finOutD\n" unless (-d $finOutD);
	my $finOut = $finOutD."$smp.MP2.txt";
	my $finOut_noV = $finOutD."$smp.MP2.noV.txt";
	my $finOut_noVB = $finOutD."$smp.MP2.noV.noB.txt";
	my $finOut_Vo = $finOutD."$smp.MP2.VirusOnly.txt";
	my $sam = "$tmpD/metph2.sam";
	#path to metaphlan DB
	my $mpDB = "/g/bork3/home/hildebra/bin/metaphlan2/db_v20/mpa_v20_m200";
	my $cmd = "mkdir -p $tmpD\n$bwt2Bin --sam-no-hd --sam-no-sq --no-unal --very-sensitive -S $sam -p $Ncore -x $mpDB -1 $inF1 -2 $inF2 \n";
	$cmd .= "$metPhl2Bin $sam --input_type sam --mpa_pkl $mpDB.pkl > $finOut\n";
	$cmd .= "$metPhl2Bin $sam --input_type sam --ignore_viruses --mpa_pkl $mpDB.pkl > $finOut_noV\n";
	$cmd .= "$metPhl2Bin $sam --input_type sam --ignore_bacteria --ignore_viruses --ignore_archaea --mpa_pkl $mpDB.pkl > $finOut_noVB\n";
	$cmd .= "$metPhl2Bin $sam --input_type sam --ignore_bacteria --ignore_eukaryotes --ignore_archaea --mpa_pkl $mpDB.pkl > $finOut_Vo\n";
	$cmd .= "rm $sam\n";
	my $mergeStr = "$metPhl2Merge *.MP2.txt > $finOutD/comb.MP2.txt";
	$cmd .= "echo \' $mergeStr \' > $stone\n";
	my $jobN = "MP2$JNUM";

	my ($jobN2,$tmpCmd) = qsubSystem($logDir."metaPhl2.sh",
			$cmd,$Ncore,"3G",$jobN,$deps,"",1,[],\%QSBopt);
	$jobN  = $jobN2;
	return $jobN;
}
sub mOTU2Mapping{
	my ($inF1a,$inF2a,$inFSa,$tmpD,$finOutD,$smp,$Ncore,$deps) = @_;
	#die "yes\n\n";
	my $stone = $finOutD."$smp.Motu2.sto";
	if (!$DoMOTU2 ||  -e $stone){return;}
	my @car1 = @{$inF1a}; my @car2 = @{$inF2a}; my @sar = @{$inFSa};
	my $inF1 = join(",",@car1); my $inF2 = join(",",@car2); my $inFS = join(",",@sar); 
	system "mkdir -p $finOutD\n" unless (-d $finOutD);
	my $cmd = "mkdir -p $tmpD\n";
	#$cmd .= "which bwa\n";
	$cmd .= "$mOTU2Bin profile ";
	$cmd .= "-f $inF1 -r $inF2 " if (@car1 > 0 );
	$cmd .= "-s $inFS " if (@sar > 0);
	$cmd .= " -n $smp -t $Ncore -q | gzip -c > $finOutD/$smp.motu2.tab.gz\n";
	$cmd .= "touch  $stone\n";
	my $jobN = "mOT$JNUM";
	#die $cmd."\n";
	my ($jobN2,$tmpCmd) = qsubSystem($logDir."mOTU2_prof.sh",
			$cmd,$Ncore,"3G",$jobN,$deps,"",1,[],\%QSBopt);
	$jobN  = $jobN2;
	return $jobN;
}


sub clean_tmp{#routine moves output from temp dirs to final dirs (that are IO limited, thus single process)
	my ($clDar,$cpref,$cpnodel,$jDepe,$tag,$curJname) = @_;
	my @clDa = @{$clDar};
	my @cps = @{$cpref};
	my @cpsND = @{$cpnodel};
	#die "@cps ==0 && @clDa ==0 && @cpsND\n";
	if (@cps ==0 && @clDa ==0 && @cpsND==0){return $jDepe;}
	my $cmd = "";
	for (my $i=0;$i<@cps;$i+=2){
		next if (length($cps[$i+1] ) < 5);
		$cmd .= "rm -r -f $cps[$i+1]\nmkdir -p $cps[$i+1]\nrsync -r --remove-source-files $cps[$i] $cps[$i+1]\n" if (@cps > 1);
	}
	for (my $i=0;$i<@cpsND;$i+=2){
		next if (length($cpsND[$i+1] ) < 5);
		$cmd .= "mkdir -p $cpsND[$i+1]\nrsync -r --remove-source-files $cpsND[$i] $cpsND[$i+1]\n"  if (@cpsND > 1);
	}
	$cmd .= "rm -f -r ".join(" ",@clDa)."\n" if (@clDa > 0  );
	$cmd .= "echo $tag >> $collectFinished\n" unless ($tag eq "");
	
	#die "@clDa\n\n$cmd\n";
	my $clnBash = $logDir."clean$curJname.sh";
	if ($curJname eq ""){
		$curJname = "_cln$JNUM";
	}
	#add extra job dependency on d2star
	my $xtraJDep = "";
	#$xtraJDep = $QSBoptHR->{rTag}."_d2met";
	my ($jdep,$tmpCmd) = ("","");
	if ($jDepe =~ m/^[\s;]+$/){
		system $cmd;#." \$" if ($cmd ne "");
	} else {
	#die "X${jDepe}X\n";
		($jdep,$tmpCmd) = qsubSystem($clnBash,$cmd,1,"1G",$curJname,$jDepe.";$xtraJDep","",1,[],\%QSBopt);
	}
	#die "jdeps: $jDepe\n$cmd\n";
	return ($jdep );
}



sub remComma($){
	my ($in) = @_;
	$in =~ s/,//g;
	return $in;
}
sub smplStats(){
	my ($inD,$assDir) = @_;
	#print "STATS   \n";
	my %ret; my $outStr = ""; my $outStrDesc = "";my $outStr5 = ""; my $outStrDesc5 = "";
	my $filStats = "";
		#return ($outStrDesc,$outStr,$outStrDesc5, $outStr5);
	$filStats = getFileStr("$inD/LOGandSUB/KrakHS.sh.etxt",0);#`cat $inD/LOGandSUB/KrakHS.sh.etxt`; chomp $filStats;
	if ($filStats ne "" ){
		if ($filStats =~ m/\d+ sequences classified \((\d+\.?\d*)%\)/){
			$outStr.= "$1%\t";
		} else {
			$outStr.= "?%\t";
		}
	} else {$outStr .= "\t" x 1;}
	$outStrDesc .= "HumanRdsPerc\t";
	
		#seq filter stats  /LOGandSUB/sdm/filter.log
	$filStats = "";
	my $MaxLengthHistBased=0;
	$filStats = getFileStr("$inD/LOGandSUB/sdm/filter_lenHist.txt",0);
	if ($filStats ne ""){
		my @tmpSpl = split(/\n/,$filStats);
		if (@tmpSpl != 0){$tmpSpl[$#tmpSpl]=~m/^(\d+)\s/; $MaxLengthHistBased= $1;}
	}
	#tmp deactivate(might still be a bug in some old sdm version):
	#$MaxLengthHistBased=0;
	#die "$MaxLengthHistBased\n";
	$filStats = "";
	if (-s "$inD/LOGandSUB/sdm/filter.log"){
		$filStats =getFileStr("$inD/LOGandSUB/sdm/filter.log",0);
	} elsif (-s "$inD/LOGandSUB/sdmReadCleaner.sh.otxt") {
		$filStats = getFileStr("$inD/LOGandSUB/sdmReadCleaner.sh.otxt",0);
	}
	if (!$readsRpairs && $filStats ne "" && $filStats =~ m/Reads processed: ([0-9,]+)/){#single end format
		my $totRds =  remComma($1);
		$filStats =~ m/Rejected: ([0-9,]+)\n/;
		#die $1. "   $2\n";
		my $Rejected1 =  remComma($1);my $Rejected2 =  0;
		$filStats =~ m/Accepted: ([0-9,]+) \(\d+/;
		my $Accepted1 =  remComma($1);my $Accepted2 =  0;
		my $Singl1 =  0;my $Singl2 =  0;
		$filStats =~ m/- Seq Length :\s*\d+.*\/(\d+.*)\/(\d+.*)\n/;
		my $AvgLen = $1; my $MaxLength=$2; if ($MaxLengthHistBased > $MaxLength){$MaxLength = $MaxLengthHistBased;}
		$filStats =~ m/- Quality :\s*\d+.*\/(\d+.*)\/\d+.*\n/;
		my $AvgQual = $1;
		$filStats =~ m/- Accum. Error (\d+\.\d+)\n/;
		my $accErr = $1;
		$outStr .= "$totRds\t$Rejected1\t$Rejected2\t$Accepted1\t$Accepted2\t$Singl1\t$Singl2\t$AvgLen\t$MaxLength\t$AvgQual\t$accErr\t";
	}elsif ($readsRpairs && $filStats ne "" && $filStats =~ m/Reads processed: ([0-9,]+); ([0-9,]+) \(pa/)
			{ #only do this if newest format
		my $totRds =  remComma($1);
		$filStats =~ m/Rejected: ([0-9,]+); ([0-9,]+)\n/;
		#die $1. "   $2\n";
		my $Rejected1 =  remComma($1);my $Rejected2 =  remComma($2);
		$filStats =~ m/Accepted: ([0-9,]+); ([0-9,]+) \(\d+/;
		my $Accepted1 =  remComma($1);my $Accepted2 =  remComma($2);
		#Singletons among these: 269,516; 6,686
		$filStats =~ m/Singletons among these: ([0-9,]+); ([0-9,]+)\n/;
		my $Singl1 =  remComma($1);my $Singl2 =  remComma($2);
		
		$filStats =~ m/- Seq Length :\s*\d+.*\/(\d+.*)\/(\d+.*)\n/;
		my $AvgLen = $1; my $MaxLength=$2;if ($MaxLengthHistBased > $MaxLength){$MaxLength = $MaxLengthHistBased;}
#		$filStats =~ m/- Seq Length :\s*\d+.*\/(\d+.*)\/\d+.*\n/;
#		my $AvgLen = $1;
		$filStats =~ m/- Quality :\s*\d+.*\/(\d+.*)\/\d+.*\n/;
		my $AvgQual = $1;
		$filStats =~ m/- Accum. Error (\d+\.\d+)\n/;
		my $accErr = $1;
		$outStr .= "$totRds\t$Rejected1\t$Rejected2\t$Accepted1\t$Accepted2\t$Singl1\t$Singl2\t$AvgLen\t$MaxLength\t$AvgQual\t$accErr\t";
		
	} else {
		$outStr .= "\t" x 11;
	}
	$outStrDesc .= "totRds\tRejected1\tRejected2\tAccepted1\tAccepted2\tSingl1\tSingl2\tAvgSeqLen\tMaxSeqLength\tAvgSeqQual\taccErr\t";
	#check for flash merged reads
	$filStats = getFileStr("$inD/LOGandSUB/flashMrg.sh.otxt",0);
	if ($filStats ne ""){
		
		if ($filStats =~ m/\[FLASH\]     Combined pairs:   (\d+)/){$outStr.="$1\t";} else {$outStr.="?\t";}
		if ($filStats =~ m/\[FLASH\]     Uncombined pairs: (\d+)/){$outStr.="$1\t";} else {$outStr.="?\t";}
	} else {
		$outStr .= "\t" x 2;
	}
	$outStrDesc .= "Merged\tNotMerged\t";
#geno size estimate
	$filStats = getFileStr("$inD/MicroCens/MC.0.result",0);
	if ($filStats ne ""){
		if ($filStats =~ m/average_genome_size:	([\d\.]+)/){$outStr.="$1\t";} else {$outStr.="?\t";}
		if ($filStats =~ m/genome_equivalents:	([\d\.]+)/){$outStr.="$1\t";} else {$outStr.="?\t";}
	} else {
		$outStr .= "\t" x 2;
	}
	$outStrDesc .= "AvgGenomeSizeEst\tTotalGenomesEst\t";
	
	
	#check if corrected dir still exists..
	system "rm -rf $inD/assemblies/metag/corrected" if (-d "$inD/assemblies/metag/corrected");
	#assembly stats
	my $tmpassD = "";
	if (-e "$inD/assemblies/metag/assembly.txt"){
		$tmpassD = getFileStr("$inD/assemblies/metag/assembly.txt",0); chomp $tmpassD;
	} elsif (-e "$inD/assemblies/metag/AssemblyStats.txt"){
		$tmpassD = "$inD/assemblies/metag/";
	} elsif (-e $assDir."metag/AssemblyStats.txt"){
		$tmpassD = "$assDir/metag/";
	}
#print $tmpassD."\n";
	my $assStats = getFileStr("$tmpassD/AssemblyStats.txt",0);
	if ($assStats ne ""){
		if ($assStats =~ m/Number of scaffolds\s+(\d+)/){ $ret{NScaff} = $1;} else { die "$tmpassD\nscfcnt wrg1\n";}
		if ($assStats =~ m/Total size of scaffolds\s+(\d+)/){ $ret{ScaffSize} = $1;} else { die "scfcnt wrg2\n";}
		if ($assStats =~ m/Longest scaffold\s+(\d+)/){ $ret{ScaffMaxSize} = $1;} else { die "scfcnt wrg3\n";}
		if ($assStats =~ m/N50 scaffold length\s+(\d+)/){ $ret{ScaffN50} = $1;} else {$ret{ScaffN50}=-1;}# die "$tmpassD\nscfcnt wrg4\n";}
		if ($assStats =~ m/Number of scaffolds > 1K nt\s+(\d+)/){ $ret{NScaffG1k} = $1;} else { die "scfcnt wrg5\n";}
		if ($assStats =~ m/Number of scaffolds > 10K nt\s+(\d+)/){ $ret{NScaffG10k} = $1;} else { die "scfcnt wrg6\n";}
		if ($assStats =~ m/Number of scaffolds > 100K nt\s+(\d+)/){ $ret{NScaffG100k} = $1;} else { die "scfcnt wrg7\n";}
		$outStr .= "$ret{NScaff}\t$ret{NScaffG1k}\t$ret{NScaffG10k}\t$ret{NScaffG100k}\t$ret{ScaffN50}\t$ret{ScaffMaxSize}\t$ret{ScaffSize}\t";
	} else {
		$outStr .= "\t" x 7;
	}
	$outStrDesc .="NScaff400\tNScaffG1k\tNScaffG10k\tNScaffG100k\tScaffN50\tScaffMaxSize\tScaffSize\t";
	
		#assembly stats
	$assStats = getFileStr("$tmpassD/AssemblyStats.500.txt",0);
	if (length($assStats) > 100){
		if ($assStats =~ m/Number of scaffolds\s+(\d+)/){ $ret{NScaff} = $1;} else { die "scfcnt wrg1\n";}
		if ($assStats =~ m/Total size of scaffolds\s+(\d+)/){ $ret{ScaffSize} = $1;} else { die "scfcnt wrg2\n";}
		if ($assStats =~ m/Longest scaffold\s+(\d+)/){ $ret{ScaffMaxSize} = $1;} else { die "scfcnt wrg3\n";}
		if ($assStats =~ m/N50 scaffold length\s+(\d+)/){ $ret{ScaffN50} = $1;} else { $ret{ScaffN50}=-1;}#die "scfcnt wrg4\n";}
		if ($assStats =~ m/Number of scaffolds > 1K nt\s+(\d+)/){ $ret{NScaffG1k} = $1;} else { die "scfcnt wrg5\n";}
		if ($assStats =~ m/Number of scaffolds > 10K nt\s+(\d+)/){ $ret{NScaffG10k} = $1;} else { die "scfcnt wrg6\n";}
		if ($assStats =~ m/Number of scaffolds > 100K nt\s+(\d+)/){ $ret{NScaffG100k} = $1;} else { die "scfcnt wrg7\n";}
		$outStr5 .= "$ret{NScaff}\t$ret{NScaffG1k}\t$ret{NScaffG10k}\t$ret{NScaffG100k}\t$ret{ScaffN50}\t$ret{ScaffMaxSize}\t$ret{ScaffSize}\t"; 
	} else {
		$outStr5 .= "\t" x 7;
	}
	$outStrDesc5 .="NScaff500\tNScaffG1k\tNScaffG10k\tNScaffG100k\tScaffN50\tScaffMaxSize\tScaffSize\t";

	#bowtie map
	my @spl = ();
		my $alignStats = getFileStr("$inD/LOGandSUB/bwtMap.sh.etxt",0);
	if (-s "$inD/LOGandSUB/bwtMap.sh.etxt"){
		@spl = split(/\n/,$alignStats);
	}
	my $idx =-1;my $dobwtStat=0;
	if (@spl > 12){
		$dobwtStat=1;
		while($spl[$idx] !~ m/\d+ reads; of these:/){
			$idx++; 
			if ($idx >= @spl){$idx=-1;last;}
		}
		if ($idx>=0 && $spl[$idx+0] =~ m/(\d+) reads; of these:/){
			$ret{totReadPairs} = $1;
		} else {
			$dobwtStat=0;#die "wrong bwtOut: $inD/LOGandSUB/bwtMap.sh.etxt X $spl[2]";
		}
	}
	if ($dobwtStat){
		if ($spl[$idx+2] =~ m/(\d+) \(.+\) aligned concordantly 0 times/){ $ret{notAlign} = $1;} else { die "bwtOut wrg1\n";}
		if ($spl[$idx+3] =~ m/(\d+) \(.+\) aligned concordantly exactly 1 time/ ){ $ret{uniqAlign} = $1;} else { die "bwtOut wrg2\n";}
		if ($spl[$idx+4] =~ m/(\d+) \(.+\) aligned concordantly >1 times/ ){ $ret{multAlign} = $1;} else { die "bwtOut wrg3  $spl[6]\n";}
		if ($spl[$idx+7] =~ m/(\d+) \(.+\) aligned discordantly 1 time/ ){ $ret{DisconcAlign} = $1;} else { die "bwtOut wrg4 $spl[9]\n";}
		if ($spl[$idx+12] =~ m/(\d+) \(.+\) aligned exactly 1 time/ ){ $ret{SinglAlign} = $1;} else { die "bwtOut wrg5 $spl[14]\n";}
		if ($spl[$idx+13] =~ m/(\d+) \(.+\) aligned >1 times/ ){ $ret{SinglAlignMult} = $1;} else { die "bwtOut wrg6 $spl[15]\n";}
		if ($spl[$idx+14] =~ m/(\d+\.\d+)\% overall alignment rate/ ){ $ret{AlignmRate} = $1;} else { die "bwtOut wrg7 $spl[16]\n";}
		$outStr .= "$ret{totReadPairs}\t$ret{AlignmRate}\t".$ret{uniqAlign}/$ret{totReadPairs}*100 ."\t".$ret{multAlign}/$ret{totReadPairs}*100 ."\t".$ret{DisconcAlign}/$ret{totReadPairs}*100 
			."\t".$ret{SinglAlign}/$ret{totReadPairs}*100 ."\t".$ret{SinglAlignMult}/$ret{totReadPairs}*100 ."\t";
		$outStr5 .= "$ret{totReadPairs}\t$ret{AlignmRate}\t".$ret{uniqAlign}/$ret{totReadPairs}*100 ."\t".$ret{multAlign}/$ret{totReadPairs}*100 ."\t".$ret{DisconcAlign}/$ret{totReadPairs}*100 
			."\t".$ret{SinglAlign}/$ret{totReadPairs}*100 ."\t".$ret{SinglAlignMult}/$ret{totReadPairs}*100 ."\t";
	} else {
		$outStr .= "\t" x 7;
		$outStr5 .= "\t" x 7;
	}
	$outStrDesc .="ReadsPaired\tOverallAlignment\tUniqueAlgned\tMultAlign\tDisconcAlign\tSingleUniqAlign\tSingleMultiAlign\t";
	$outStrDesc5 .="ReadsPaired\tOverallAlignment\tUniqueAlgned\tMultAlign\tDisconcAlign\tSingleUniqAlign\tSingleMultiAlign\t";
	
	#novocraft sort
	my $doDup = 0;my $alignStats2 = getFileStr("$inD/LOGandSUB/bwtMap2.sh.etxt",0);
	if ($alignStats2 ne "" ){if (defined ($alignStats2)){$doDup=1;}}
	if ($doDup){
		
		#print "$alignStats2 YUYS\n";
		if ($alignStats2 =~ m/Proper Pairs\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/){$ret{EstLibSize} = $4; $ret{duplOptic} = $3; $ret{duplPCR} = $2; $ret{duplPass} = $1;} else {$doDup=0;}#die "Can't find dupl stats: $alignStats2\n";}
		if ($alignStats2 =~ m/Improper Pairs\s+(\d+)\s+(\d+)\s+(\d+)/){$ret{duplOptic} += $3; $ret{duplPCR} += $2; $ret{duplPass} += $1;} else {$doDup=0;}#{die "Can't find impr. dupl stats: $alignStats2\n";}
	}
	if ($doDup){
		$outStr .= "$ret{duplOptic}\t$ret{duplPCR}\t$ret{duplPass}\t$ret{EstLibSize}\t";
		$outStr5 .= "$ret{duplOptic}\t$ret{duplPCR}\t$ret{duplPass}\t$ret{EstLibSize}\t";
	} else {
		$outStr .= "\t" x 3;
		$outStr5 .= "\t" x 3;
	}
	$outStrDesc .= "OpticalDuplicates\tPCRduplicates\tPassedMD\tBS_estLibSize\t";
	$outStrDesc5 .= "OpticalDuplicates\tPCRduplicates\tPassedMD\tBS_estLibSize\t";
	#die "$inD/assemblies/metag/ContigStats/GeneStats.txt";
if (-e "$inD/assemblies/metag/ContigStats/GeneStats.txt"){	
		open I,"<$inD/assemblies/metag/ContigStats/GeneStats.txt"; 
		#GeneNumber	AvgGeneLength	AvgComplGeneLength	BpGenes	BpNotGenesGcomplete	G5pComplete	G3pComplete	Gincomplete
		my $tmp = <I>;$outStrDesc .= $tmp;$outStrDesc5 .= $tmp;
		$tmp = <I>; $outStr .= $tmp; $outStr5 .= $tmp; 
		close I;
	} else {
		$outStrDesc .= "GeneNumber	AvgGeneLength	AvgComplGeneLength	BpGenes	BpNotGenesGcomplete	Gcomplete	G5pComplete	G3pComplete	Gincomplete";
		$outStrDesc5 .= "GeneNumber	AvgGeneLength	AvgComplGeneLength	BpGenes	BpNotGenesGcomplete	Gcomplete	G5pComplete	G3pComplete	Gincomplete";
		$outStr .= "\t" x 7;$outStr .= "\t" x 7;
	}
	chomp $outStrDesc; chomp $outStr;chomp $outStrDesc5; chomp $outStr5;
#	my @gest = split(/\t/,$gsta);
	#my $nGenes = `wc -l $inD/assemblies/metag/genePred/genes.gff | cut -f1 -d ' '`;	chomp $nGenes;
	#die ($outStr."\n$nGenes\n");
#	$outStr .= "$nGenes\t";	$outStrDesc .= "NumGenes\t";


	return ($outStrDesc,$outStr,$outStrDesc5, $outStr5);
	#die $outStr."\n";
}

sub readG2M($){
	my ($inf) = @_;
	open K,"<",$inf;
	my %COGs2motus;
	my %motus;
	while (my $li = <K>){
		chomp($li);
		my @spl = split("\t",$li);
		$motus{$spl[0]} = $spl[3];
		$COGs2motus{$spl[0]} = $spl[2];
	}
	close K;
	print "Read gene to map file\n";
}

sub ReadsFromMapping{
	my ($tmpFile,$linkFile) = @_;
	my $newOfile = ""; my $GID = "";
	open TO,">",$linkFile;
	open I,"<",$tmpFile;
	while (my $line = <I>){
		chomp($line);
		my @spl = split("\t",$line);
		my $readID = $spl[0];
		my $geneMtch = $spl[2];
		#get read and genomeMatch
		#unless (exists($motus{$geneMtch})){print "could not find gene ID $geneMtch\n"; next;}
		#my $newHd = "@".$COGs2motus{$geneMtch}."___".$motus{$geneMtch};
		$newOfile = $GID.".rdM";
		#die ($newOfile);
		
		$readID=~m/(.*)#/;
		print TO $1."\t"."\t".$newOfile."\n";#$newHd."\n".$spl[9]."\n+\n".$spl[10]."\n";
		#die;
	}
	close TO;
	close I;
}

sub RayAssembly(){
 "mpiexec -n 1 /g/bork5/hildebra/bin/Ray-2.3.1/ray-build/Ray -o test -p test/test_1.fastq test/test_2.fastq -k 31"
 }
 
 
 sub createPsAssLongReads(){
	my ($arp1,$arp2,$singAr,$jdep, $pseudoAssFile, $Fdir, $smplName) = @_;
	my @allRds = (@{$arp1},@{$arp2},@{$singAr});
	my $psDir = $pseudoAssFile; $psDir =~ s/[^\/]+$//;
	my $psFinal = $pseudoAssFile; $psFinal =~ s/^.+\//$Fdir\//;
	#die $psFinal;
	my $pseudoAssFileFlag = $pseudoAssFile.".sto";
	
	my $psFile = $pseudoAssFile;#"$finalCommAssDir/longReads.fasta.filt";
	if (-d $psFinal){system "rm -r $psFinal";}
	if (!-e $pseudoAssFile && -e $psFinal && -e $psFinal.".sto"){
		$pseudoAssFileFlag = $psFinal.".sto"; 
		$psFile = $psFinal;
	}

	#die "@allRds\n";
	my $cmd = "";
	$cmd .= "mkdir -p $psDir $Fdir\n";
	$cmd .= "$sizFiltScr ".join(",",@allRds)." 400 -1 $pseudoAssFile\n";
	$cmd .= "$renameCtgScr $psFile $smplName\n";
	$cmd .= "touch $pseudoAssFileFlag\n";
	#die $cmd;
	my ($jname,$tmpCmd) = ("","");
	if (!-e $pseudoAssFileFlag || !-e $psFinal.".sto"){
		$jname = "_PA$JNUM";;
		($jname,$tmpCmd) = qsubSystem($logDir."pseudoAssembly.sh",$cmd,1,"5G",$jname,$jdep,"",1,\@General_Hosts,\%QSBopt) ;
	} else {$cmd="";}
	my $megDir = $psFile; $megDir =~ s/[^\/]+$//;
	#die "$megDir\n";
	return ($jname,$psFile, $megDir);
 }

 
sub spadesAssembly(){
	my ($asHr,$cAssGrpX,$nodeTmp,$finalOut,$doClean,$helpAssembl,$smplName,$hostFilter,$libInfoRef,$mateFlag) = @_;
	
	my $p1ar = $AsGrps{$cAssGrpX}{FilterSeq1};
	my $p2ar = $AsGrps{$cAssGrpX}{FilterSeq2};
	my $singlAr = $AsGrps{$cAssGrpX}{FilterSeqS};
	my $jDepe = $AsGrps{$cAssGrpX}{SeqClnDeps};
	#print all samples used 
	my $nCores = $Assembly_Cores;#6
	my $noTmpOnNode = 0; #prevent usage of tmp space on node
	if ($noTmpOnNode){
		$nodeTmp = $finalOut;
	}
 	my $cmd = "rm -rf $nodeTmp\nmkdir -p $nodeTmp\nmkdir -p $finalOut\n\n";
	$cmd .= "\necho '". $AsGrps{$cAssGrpX}{AssemblSmplDirs}. "' > $nodeTmp/smpls_used.txt\n\n";
	my $defTotMem = $Assembly_Memory;#60;
	my $defMem = ($defTotMem/$nCores);
	$defTotMem = $defMem * $nCores; #total really available mem (in GB)

	$cmd .= $spadesBin;
	my $K = $Assembly_Kmers ;
	#insert single reads
	my $errStep = "";
	$errStep = "--only-assembler " if ($doClean == 0);
	my $numInLibs = scalar @{$p1ar};
	my $sprds = inputFmtSpades($p1ar,$p2ar,$singlAr,$logDir);
	if ($numInLibs <= 1) {$cmd .= " --meta " ;} else {$cmd .= " --sc " ;} #deactivated as never done with other T2 samples..
	$cmd .= " $K $sprds -t $nCores $errStep -m $defTotMem ";#--mismatch-correction "; # --meta  --sc "; #> $log #--meta :buggy in 3.6
	$cmd .= " --mismatch-correction " if ($spadesMisMatCor);
	if ($helpAssembl ne ""){
		$cmd .= "--untrusted-contigs $helpAssembl ";
	}
	$cmd .= "-o $nodeTmp\n";
	#from here could as well be separate 1 core job
	#cleanup assembly
	$cmd .= "\nrm -f -r $nodeTmp/K* $nodeTmp/tmp $nodeTmp/mismatch_corrector/*\n";
	#dual size filter
	$cmd .= "$renameCtgScr $nodeTmp/scaffolds.fasta $smplName\n";
	$cmd .= "$sizFiltScr $nodeTmp/scaffolds.fasta 400 200\n";
	
	if ($JNUM > 1 && $helpAssembl ne ""){
		#cluster short reads using CD-HIT, replaces scaffolds.fasta.filt2 file
		my $secAss = $nodeTmp."secondary_shorts/";
		$cmd .= "mkdir -p $secAss\n";
		$cmd .= "cat $nodeTmp/scaffolds.fasta >> $nodeTmp/scaffolds.fasta2\n";
		$cmd .= $spadesBin." -s $nodeTmp/scaffolds.fasta2 --only-assembler -m 1000 -t $nCores $K -o $secAss\n";
		#cleanup
		$cmd .= "cp  $secAss/contigs.fasta $nodeTmp/scaffolds.fasta2\nrm -f -r $secAss\n";
	}
	$cmd .= "$assStatScr -scaff_size 500 $nodeTmp/scaffolds.fasta > $nodeTmp/AssemblyStats.500.txt\n";
	$cmd .= "$assStatScr $nodeTmp/scaffolds.fasta > $nodeTmp/AssemblyStats.ini.txt\n";
	$cmd .= "$assStatScr $nodeTmp/scaffolds.fasta.filt > $nodeTmp/AssemblyStats.txt\n";

	my ($cmdDB,$bwtIdx) = buildMapperIdx("$nodeTmp/scaffolds.fasta.filt",$nCores,0,$MapperProg);#$nCores);
	$cmd .= $cmdDB unless($mateFlag || !$map2Assembly); #doesn't need bowtie index
	
	#clean up
	$cmd .= "\n $pigzBin -p $nCores -r $nodeTmp/scaffolds.fasta $nodeTmp/misc/\n $pigzBin -p $nCores -r $nodeTmp/assembly_graph.gfa  $nodeTmp/contigs.paths $nodeTmp/before_rr* $nodeTmp/*contigs.fa* $nodeTmp/*.fastg\n";
	$cmd .=  "rm -rf $nodeTmp/corrected\n";
	unless ($noTmpOnNode){
		$cmd .=  "mkdir -p $finalOut\ncp -r $nodeTmp/* $finalOut\n" ;
		$cmd .= "rm -rf $nodeTmp\n";
	}
	my $jname = "";
	
	if (-e $logDir."spaderun.sh.otxt"){	#check for out of mem
		open I,"<$logDir/spaderun.sh.otxt" or die "Can't open old assembly logfile $logDir\n"; my $str = join("", <I>); close I;
		if ($str =~ / Error in malloc(): out of memory/ ||$str =~ m/TERM_MEMLIMIT: job killed after reaching LSF memory usage limit/){ #memory error for real
			my $replMem  = "";
			if ($str =~ /\n    Max Memory :     (\d+) MB\n/){	$replMem = int($1*1000/$nCores*1.7);
			} elsif ($str =~ /\nMAX MEM (\d+)G\n/){	$replMem = int($1/$nCores*1.7);}
			unless ($replMem eq ""){
				if (($replMem *$nCores)< 50){$replMem = 12;} 
				$defMem = $replMem;
				print $defMem."G: new MEM\n"; #die $defMem."\n";
			}
		}
	}
	$cmd .= "echo \"MAX MEM ".$defTotMem."G\"";
	#print "in Assembly\n$jDepe\n";
	#print "$finalOut/scaffolds.fasta.filt\n";
	unless (-e "$finalOut/scaffolds.fasta.filt" && !-z "$finalOut/scaffolds.fasta.filt" && !-z "$finalOut/AssemblyStats.txt"){
		#my $size_in_mb = (-s $fh) / (1024 * 1024);
		my $tmpCmd="";
		$jname = "_A$JNUM";#$givenJName;
		$QSBopt{useLongQueue} = 1;
		if ($hostFilter || $SpadesAlwaysHDDnode){
			my $tmpSHDD = $QSBopt{tmpSpace};
			$QSBopt{tmpSpace} = $Spades_HDspace."G" unless ($Spades_HDspace =~ m/G$/); #set option how much tmp space is required, and reset afterwards
			($jname,$tmpCmd) = qsubSystem($logDir."spaderun.sh",$cmd,(int($nCores/2)+1),int($defMem*2)."G",$jname,$jDepe,"",1,\@Spades_Hosts,\%QSBopt) ;
			$QSBopt{tmpSpace} = $tmpSHDD;
		} else {
			($jname,$tmpCmd) = qsubSystem($logDir."spaderun.sh",$cmd,(int($nCores/2)+1),int($defMem*2)."G",$jname,$jDepe,"",1,\@General_Hosts,\%QSBopt) ;
		}
		$QSBopt{useLongQueue} = 0;
	} else {
		print "Assembly still on tmp dir\n";
	}
	#die("SPADE\n");
	return ($jname);
}



sub megahitAssembly(){
	my ($asHr,$cAssGrpX,$nodeTmp,$finalOut,$doClean,$helpAssembl,$smplName,$hostFilter,$libInfoRef,$mateFlag) = @_;
	
	my $p1ar = $AsGrps{$cAssGrpX}{FilterSeq1};
	my $p2ar = $AsGrps{$cAssGrpX}{FilterSeq2};
	my $singlAr = $AsGrps{$cAssGrpX}{FilterSeqS};
	my $jDepe = $AsGrps{$cAssGrpX}{SeqClnDeps};
	#print all samples used 
	my $nCores = $Assembly_Cores;#6
	my $noTmpOnNode = 0; #prevent usage of tmp space on node
	if ($noTmpOnNode){
		$nodeTmp = $finalOut;
	}
	my $nodePreD = $nodeTmp;$nodePreD=~s/\/[^\/]+\/*$/\//;
	#die "$nodePreD\n$nodeTmp\n";
	
 	my $cmd = "rm -rf $nodeTmp\nmkdir -p $nodePreD $finalOut\n\n"; #\n  mkdir -p $nodeTmp/tmp\n
	my $defTotMem = $Assembly_Memory;#60;
	my $defMem = ($defTotMem/$nCores);
	$defTotMem = $defMem * $nCores; #total really available mem (in GB)

	my $K = $Assembly_Kmers ;
	$K =~ s/-k //;
	#check that k's are closer than 28
	my @spl  = sort {$a <=> $b}(split /,/,$K);
	for (my $i=1;$i<@spl;$i++){
		if ($spl[$i] - $spl[$i-1] > 28){die "kmers for megahit: $K: steps must be <28\n";}
	}
	$K = join(",",@spl);
	#insert single reads
	my $numInLibs = scalar @{$p1ar};
	my $sprds = inputFmtMegahit($p1ar,$p2ar,$singlAr,$logDir);
	$cmd .= $megahitBin;
	$cmd .= " --k-list $K $sprds -t $nCores -m ".$defTotMem*1024*1024*1024 ." --out-prefix megaAss ";
	if ($helpAssembl ne ""){
		$cmd .= "--untrusted-contigs $helpAssembl ";
	}
	$cmd .= "-o $nodeTmp  \n";  #--tmp-dir $nodeTmp/tmp/
	#from here could as well be separate 1 core job
	#cleanup assembly
	$cmd .= "\necho '". $AsGrps{$cAssGrpX}{AssemblSmplDirs}. "' > $nodeTmp/smpls_used.txt\n\n";
	$cmd .= "\nrm -fr $nodeTmp/tmp/ $nodeTmp/intermediate_contigs/ \nmv $nodeTmp/megaAss.contigs.fa $nodeTmp/scaffolds.fasta\n\n";
	#dual size filter
	$cmd .= "$renameCtgScr $nodeTmp/scaffolds.fasta $smplName\n";
	$cmd .= "$sizFiltScr $nodeTmp/scaffolds.fasta 400 200\n";
	
	if ($JNUM > 1 && $helpAssembl ne ""){
		#cluster short reads using CD-HIT, replaces scaffolds.fasta.filt2 file
		my $secAss = $nodeTmp."secondary_shorts/";
		$cmd .= "mkdir -p $secAss\n";
		$cmd .= "cat $nodeTmp/scaffolds.fasta >> $nodeTmp/scaffolds.fasta2\n";
		$cmd .= $spadesBin." -s $nodeTmp/scaffolds.fasta2 --only-assembler -m 1000 -t $nCores $K -o $secAss\n";
		#cleanup
		$cmd .= "cp  $secAss/contigs.fasta $nodeTmp/scaffolds.fasta2\nrm -f -r $secAss\n";
	}
	$cmd .= "$assStatScr -scaff_size 500 $nodeTmp/scaffolds.fasta > $nodeTmp/AssemblyStats.500.txt\n";
	$cmd .= "$assStatScr $nodeTmp/scaffolds.fasta > $nodeTmp/AssemblyStats.ini.txt\n";
	$cmd .= "$assStatScr $nodeTmp/scaffolds.fasta.filt > $nodeTmp/AssemblyStats.txt\n";
	
	my ($cmdDB,$bwtIdx) = buildMapperIdx("$nodeTmp/scaffolds.fasta.filt",$nCores,0,$MapperProg);#$nCores);
	$cmd .= $cmdDB unless($mateFlag || !$map2Assembly); #doesn't need bowtie index
	
	#clean up
	$cmd .= "\n $pigzBin -p $nCores $nodeTmp/scaffolds.fasta\n";
	unless ($noTmpOnNode){
		$cmd .=  "mkdir -p $finalOut\ncp -r $nodeTmp/* $finalOut\n" ;
		$cmd .= "rm -rf $nodeTmp\n";
	}
	my $jname = "";
	
#	if (-e $logDir."megahitrun.sh.otxt"){	#check for out of mem
#	}
	$cmd .= "echo \"MAX MEM ".$defTotMem."G\"";
	#die "$cmd\n\n";
	#print "in Assembly\n$jDepe\n";
	#print "$finalOut/scaffolds.fasta.filt\n";
	unless (-e "$finalOut/scaffolds.fasta.filt" && !-z "$finalOut/scaffolds.fasta.filt" && !-z "$finalOut/AssemblyStats.txt"){
		#my $size_in_mb = (-s $fh) / (1024 * 1024);
		my $tmpCmd="";
		$jname = "mA$JNUM";#$givenJName;
		$QSBopt{useLongQueue} = 0;#super fast, doesn't need long queue
		if ($hostFilter || $SpadesAlwaysHDDnode){
			my $tmpSHDD = $QSBopt{tmpSpace};
			$QSBopt{tmpSpace} = $Spades_HDspace."G" unless ($Spades_HDspace =~ m/G$/); #set option how much tmp space is required, and reset afterwards
			($jname,$tmpCmd) = qsubSystem($logDir."megahitrun.sh",$cmd,(int($nCores)),int($defMem)."G",$jname,$jDepe,"",1,\@Spades_Hosts,\%QSBopt) ;
			$QSBopt{tmpSpace} = $tmpSHDD;
		} else {
			($jname,$tmpCmd) = qsubSystem($logDir."megahitrun.sh",$cmd,(int($nCores)),int($defMem)."G",$jname,$jDepe,"",1,\@General_Hosts,\%QSBopt) ;
		}
		$QSBopt{useLongQueue} = 0;
	} else {
		print "Assembly still on tmp dir\n";
	}
	#die("SPADE\n");
	return ($jname);
}
#GenePrediction
sub run_prodigal($ $ $ $) {
	my ($inputScaff, $outDir, $jobDepend,$finDir,$specJname) = @_;
	#system("mkdir -p $outDir");
	my $prodigalBin = "/g/bork5/hildebra/bin/Prodigal-2.6.1/prodigal";
	my $output_format_prodigal = "gff"; 
	my $expectedD = "$finDir/assemblies/metag/genePred";
	my $prodigal_cmd = "mkdir -p $outDir\n";
	$prodigal_cmd .= ("$prodigalBin -i $inputScaff -o $outDir/genes.gff -a $outDir/proteins.faa -d $outDir/genes.fna -f $output_format_prodigal -p meta\n");
	$prodigal_cmd .= "sleep 2;cut -f1 -d \" \" $outDir/proteins.faa > $outDir/proteins.shrtHD.faa\n" ;
	$prodigal_cmd .= "cut -f1 -d \" \" $outDir/genes.fna > $outDir/genes.shrtHD.fna\n" ;
	$prodigal_cmd .= "rm -f $outDir/proteins.faa $outDir/genes.fna";
	
	#if (!-e "$inputScaff") {die "Input scaffold $inputScaff does not exists.\n";}
	#print $prodigal_cmd."\n";
	#if (system $prodigal_cmd){die "Finished prodigal with errors";}
	my $jname = "";
	#print "$expectedD/proteins.shrtHD.faa\n$expectedD/genes.gff\n";
	if ( (!-s "$expectedD/proteins.shrtHD.faa" || !-s "$expectedD/genes.gff")){
		if (!-s "$outDir/proteins.shrtHD.faa" || !-s "$outDir/genes.gff"){
			$jname = "_GP$JNUM"; my $tmpCmd="";
			$jname = $specJname.$JNUM if ($specJname ne "");
			#print "genesubm\n";
			($jname,$tmpCmd) = qsubSystem($logDir."prodigalrun.sh",$prodigal_cmd,1,"1G",$jname,$jobDepend,"",1,\@General_Hosts,\%QSBopt); 
		}
	}
	return $jname;
}
sub run_prodigal_augustus($ $ $ $) {
	my ($inputScaff, $outDir, $jobDepend,$finDir,$specJname,$GlbTmpPath) = @_;
	my $tmpGene = $outDir."/tmpCalls/";
	#system("mkdir -p $outDir");
	my $scrDir = "/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/helpers/euk_gene_caller/bin";
	my $output_format_prodigal = "gff"; 
	my $expectedD = "$finDir/genePred";
	my $augCmd  = ""; my $cmpCmd = "";
	my $tmpCmd=""; #placeholder for qsub return
	my $splitDep = $jobDepend;
	my $inputBac = $inputScaff; my $inputEuk = "$GlbTmpPath/euk.kraken.fasta";
	my $bacmark="";
	if ($DO_EUK_GENE_PRED ){ $bacmark = ".bac";	}
	
	#print "$outDir/proteins$bacmark.shrtHD.faa\n";
	
	if ( (-s "$expectedD/proteins$bacmark.shrtHD.faa" || -s "$expectedD/genes$bacmark.gff") &&
			(-s "$outDir/proteins$bacmark.shrtHD.faa" || -s "$outDir/genes$bacmark.gff") ){
		return "";
	}
	#use kraken to classify contigs..
	if ($DO_EUK_GENE_PRED ){ #stupid way of doing things..
		#first split euk vs bac contigs
		my $splCores = 10;
		my ($refDB,$shrtDB,$clnCmd) = prepDiamondDB("NOG",$globaldDiaDBdir,$splCores);
		my $scmd = "mkdir -p $outDir\n";
		$scmd .= "$splitKgdContig $inputScaff $GlbTmpPath $krakenDBDirGlobal $globaldDiaDBdir $splCores\n";
		$scmd .= "touch $GlbTmpPath/bac.euk.split.sto\n";
		#die $scmd."\n";
		$inputBac = "$GlbTmpPath/bact.kraken.fasta";
		#die "$inputEuk || !-e $inputBac\n";
		if (!-e $inputEuk || !-e $inputBac || !-e "$GlbTmpPath/bac.euk.split.sto"){
			($splitDep,$tmpCmd) = qsubSystem($logDir."splitAssembly.sh",$scmd,$splCores,int(50/$splCores)."G","_SC$JNUM","$jobDepend;$krakDeps","",1,\@General_Hosts,\%QSBopt); 
		}
	}

#die "toofar";
	my $prodigal_cmd = "";
	$prodigal_cmd .= "mkdir -p $tmpGene $outDir\n";
		
		$prodigal_cmd.="if [ ! -s $inputBac ];then\n";
		$prodigal_cmd.="touch $tmpGene/proteins$bacmark.shrtHD.faa $tmpGene/genes$bacmark.per.ctg $tmpGene/genes$bacmark.shrtHD.fna $tmpGene/genes$bacmark.gff\n";
		$prodigal_cmd.="else\n";
	
	$prodigal_cmd .= ("$prodigalBin -i $inputBac -o $tmpGene/genes$bacmark.gff -a $tmpGene/proteins.faa -d $tmpGene/genes.fna -f $output_format_prodigal -p meta\n");
	$prodigal_cmd .= "sleep 2;cut -f1 -d \" \" $tmpGene/proteins.faa > $tmpGene/proteins$bacmark.shrtHD.faa\n" ;
	$prodigal_cmd .= "cut -f1 -d \" \" $tmpGene/genes.fna > $tmpGene/genes$bacmark.shrtHD.fna\n" ;
	$prodigal_cmd .= "cut -f1 $tmpGene/genes$bacmark.gff | sort | uniq -c | grep -v '#' |  awk -v OFS='\\t' {'print \$2, \$1'} > $tmpGene/genes$bacmark.per.ctg\n";
	$prodigal_cmd .= "rm -f $tmpGene/proteins.faa $tmpGene/genes.fna\n";	
	#copy everything to the right place (for now, might have to change this later to take care of Eukarya)
	$prodigal_cmd .= "mkdir -p $expectedD\n";
		
	$prodigal_cmd.="fi\n";
	
	
	
	if ($DO_EUK_GENE_PRED ){ #stupid way of doing things..
		#1st set mark that prodigal genes are on bacteria only
		$prodigal_cmd .= "touch $tmpGene/genes.prodigal.bact.only\n";
		$augCmd .= "mkdir -p $tmpGene\n";
		my $eukmark = ".euk";

		$augCmd.="if [ ! -s $inputEuk ];then\n";
		$augCmd.="touch $tmpGene/genes$eukmark.gff $tmpGene/genes$eukmark.codingseq $tmpGene/genes$eukmark.fna\n";
		$augCmd.="else\n";
		$augCmd .= "$augustusBin --species=ustilago_maydis $inputEuk --protein=off --codingseq=on > $tmpGene/augustus.gff;\n";
		$augCmd .= "perl $scrDir/getAnnoFast.pl --seqfile=$inputEuk $tmpGene/augustus.gff;";
		$augCmd.="mv $tmpGene/augustus.gff $tmpGene/genes$eukmark.gff\n mv $tmpGene/augustus.codingseq $tmpGene/genes$eukmark.codingseq\nmv $tmpGene/augustus.cdsexons $tmpGene/genes$eukmark.fna\n";
		$augCmd .= "cut -f1 -d \" \" $tmpGene/genes$eukmark.fna > $tmpGene/genes$eukmark.shrtHD.fna\n" ;
		$augCmd .= "rm $tmpGene/genes$eukmark.fna\n";
		$augCmd.="fi\n";

		
		my $axl = "$tmpGene/augustus.list"; my $pxl = "$tmpGene/genes.list";
		my $cmpCmd = "grep -v \"^#\" $tmpGene/genes.gff > $pxl;\n";
		$cmpCmd .= "grep -w \"transcript\" $tmpGene/augustus.gff > $axl;\n";
		$cmpCmd .= "grep \">\" $inputEuk > $tmpGene.scaff.list;\n";
		$cmpCmd .= "awk \'!/^>/ { printf \"%s\", $0; n = \"\n\" } /^>/ { print n $0; n = \"\" } END { printf \"%s\", n }\' $tmpGene/augustus.codingseq > $axl.nolines.fa;\n";
		$cmpCmd .= "awk \'!/^>/ { printf \"%s\", $0; n = \"\n\" } /^>/ { print n $0; n = \"\" } END { printf \"%s\", n }\' $tmpGene/genes.shrtHD.fna > $pxl.nolines.fa;\n";
		$cmpCmd .= "perl $scrDir/process_nodes.pl $pxl $axl;\n";
		$cmpCmd .= "perl $scrDir/match_nodes_euk.pl $axl.output.txt $axl.nolines.fa;\n";
		$cmpCmd .= "perl $scrDir/match_nodes_bac.pl $pxl.output.txt $pxl.nolines.fa;\n";
		$cmpCmd .= "perl $scrDir/overlap_nodes.pl $tmpGene.scaff.list $axl.output.txt $pxl.list.output.txt ;\n"; #$f.blast.matched.txt
		$cmpCmd .= "perl $scrDir/finalgeneparsing.pl $tmpGene.scaff.list.ALLmatched.txt\n";
		#now, let's pull the appropriated gene. for each contig, need to retrieve ALL genes for that contig.
		$cmpCmd .= "cut -f 4 $tmpGene.scaff.list.ALLmatched.txt.decision.txt | sort |uniq> $tmpGene/formatching.txt\n";
		#$cmpCmd .= "perl ./bin/getgenes.pl $tmpGene/formatching.txt $f.aug.nolines.fa.renamed.fa \n";
		#$cmpCmd .= "perl ./bin/getgenes.pl $tmpGene/formatching.txt $f.mgm.nolines.fa.renamed.fa\n";
		#$cmpCmd .= "cat $f.aug.nolines.fa.renamed.fa.output.txt $f.mgm.nolines.fa.renamed.fa.output.txt > $f.genecalled.fa\n";
		#die $augCmd;
	}
	
	#finish up file transfer etc
	$prodigal_cmd .= "mv $tmpGene/* $outDir\nrm -r $tmpGene\n";

	#if (!-e "$inputScaff") {die "Input scaffold $inputScaff does not exists.\n";}
	#die $prodigal_cmd."\n";
	#if (system $prodigal_cmd){die "Finished prodigal with errors";}
	my $jname = "";
	#print "$expectedD/proteins.shrtHD.faa\n$expectedD/genes.gff\n";
	if ( (!-s "$expectedD/proteins$bacmark.shrtHD.faa" || !-s "$expectedD/genes$bacmark.gff") &&
			(!-s "$outDir/proteins$bacmark.shrtHD.faa" || !-s "$outDir/genes$bacmark.gff") ){
		$jname = "_GP$JNUM"; 
		$jname = $specJname.$JNUM if ($specJname ne "");
		#print "genesubm\n";
		($jname,$tmpCmd) = qsubSystem($logDir."prodigalrun.sh",$augCmd.$prodigal_cmd,1,"1G",$jname,$splitDep,"",1,\@General_Hosts,\%QSBopt); 

	}
	return $jname;
}

sub filterSizeFastaCmd(){
my ($fasta,$siz,$siz2) = @_;
my $cmdd= ("/g/bork3/home/hildebra/dev/Perl/assemblies/./sizeFilterFas.pl $fasta $siz $siz2");
return ($fasta.".filt",$cmdd);
}

sub annoucnce_MATAFILER{
	print "This is MATAFILER $MATFILER_ver\n";
}
sub help {
	print "Help for MATAFILER version $MATFILER_ver\n";
	exit(0);
}






