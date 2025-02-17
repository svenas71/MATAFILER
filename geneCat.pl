#!/usr/bin/env perl
#script to create secondary summary stats over MATAFILER runs
#1) creates a gene catalog from predicted genes using cd-hit-est
#2) sums up diamond tables -> moved to helper script "combine_DIA.pl"
#3) makes marker genes to proteins
#4) assigns diamond(FuncAssign) / FOAM to gene finished gene catalog
#usage: ./geneCat.pl [mappingFile] [in/outdir]
#ex ./geneCat.pl /g/bork5/hildebra/data/metaGgutEMBL/MM_at_v5_T2subset.txt /g/scb/bork/hildebra/SNP/GCs/T2_HM3_GNM3_ABR 1 95
#ex ./geneCat.pl /g/bork5/hildebra/data/metaGgutEMBL/MM_at_v3.txt,/g/bork5/hildebra/data/metaGgutEMBL/ABRtime.txt /g/scb/bork/hildebra/SNP/GCs/GNM3_ABR 1 95
#for Jure ./geneCat.pl /g/bork5/hildebra/data/metaGgutEMBL/ABRtime.txt /g/scb/bork/hildebra/SNP/GCs/JureTest 1 95
#ex ./geneCat.pl /g/bork5/hildebra/data/metaGgutEMBL/simus2.txt /g/scb/bork/hildebra/SNP/GCs/SimuB 1 95 /g/bork3/home/hildebra/data/TAMOC/FinSoil/GlbMap/extraGenes_sm.fna /g/bork3/home/hildebra/data/TAMOC/FinSoil/GlbMap/extraGenes_all.faa
#ex ./geneCat.pl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/maps/soil_ex.map,/g/scb/bork/hildebra/data2/refData/Soil/PNAS_refs/other_soil.map,/g/scb/bork/hildebra/data2/refData/Soil/howe2014/iowa.map,/g/scb/bork/hildebra/data2/Soil_finland/soil_map.txt /g/scb/bork/hildebra/SNP/GCs/SoilCatv3 1 95 /g/bork3/home/hildebra/data/TAMOC/FinSoil/GlbMap/extraGenes_all.fna /g/bork3/home/hildebra/data/TAMOC/FinSoil/GlbMap/extraGenes_all.faa
#ex ./geneCat.pl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/maps/drama2.map /g/scb/bork/hildebra/SNP/GCs/DramaGCv3.1 1 95
#ex ./geneCat.pl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/maps/ 1 95
#faa generation from gene  catalog 
#ex ./geneCat.pl ? /g/bork1/hildebra/SNP/GC/T2_GNM3_ABR protExtract 
#./geneCat.pl ? /g/scb/bork/hildebra/SNP/GNMass2_singl/ 1 95
#./geneCat.pl MGS /g/scb/bork/hildebra/SNP/GCs/  #canopy clustering
#./geneCat.pl FuncAssign /g/scb/bork/hildebra/SNP/GCs/ #FAOM eggNOG assignment of genes
#./geneCat.pl FMG_extr /g/scb/bork/hildebra/SNP/GCs/SimuGC/  #gets FMGs in separate folder
use warnings;
use strict;
use File::Basename;
use Cwd; use English;
use Mods::GenoMetaAss qw( splitFastas readMapS qsubSystem emptyQsubOpt systemW readGFF);
use Mods::IO_Tamoc_progs qw(getProgPaths);
use Mods::TamocFunc qw(attachProteins attachProteins2 getSpecificDBpaths);
use Mods::FuncTools qw(assignFuncPerGene calc_modules);
use Mods::geneCat qw(readGeneIdx);

sub readCDHITCls;sub readFasta; 
sub writeBucket; sub submCDHIT;
sub mergeClsSam; sub secondaryCls;
sub cleanUpGC; sub nt2aa; sub clusterFNA;
#sub systemW; #system execution (stops this program upon error)
sub protExtract; #extracts proteins seqs for each cluster
sub combineClstr;#rewrites cd-hit cluster names to my gene Idx numbers
sub rewriteFastaHdIdx; #replaces ">MM2__C122;_23" with number from gene catalog
sub FOAMassign;
sub geneCatFunc;
sub readSam;
sub canopyCluster; #MGS creation
sub krakenTax; #assign tax to each gene via kraken
sub kaijuTax; #assign tax to each gene via kraken
sub specITax;
sub writeMG_COGs;

#.27: added external genes support
#.28: gene length filter
my $version = 0.30;
my $justCDhit = 0;
my $bactGenesOnly = 0; #set to zero if no double euk/bac predication was made
my $doSubmit = 1; my $qsubNow = 0;
my $oldNameFolders= 0;
my $doFMGseparation = 1; #cluster FMGs separately?
my $doGeneMatrix =1; #in case of SOIL I really don't need to have a gene abudance matrix / sample
my $numCor = 40; my $totMem = 700; #in G

my $toLclustering=0;#just write out, no sorting etc




die "Not enough Args\n" if (@ARGV < 2);
my $mapF = $ARGV[0];#"/g/bork5/hildebra/data/metaGgutEMBL/MM.txt";
my $baseOut = "";
$baseOut = $ARGV[1] if (@ARGV > 1);#"/g/scb/bork/hildebra/SNP/GNMass/";
#die $mapF."\n@ARGV\n";
my $BIG = 0;
$BIG = $ARGV[2] if (@ARGV > 2);
my $cdhID = 95; my $minGeneL = 100;
$cdhID = $ARGV[3] if (@ARGV > 3);
my $extraRdsFNA = "";
$extraRdsFNA = $ARGV[4] if (@ARGV > 4);#FNA with (predicted) genes, that are to be artificially added to the new gene catalog (and clutered with new genes)
my $extraRdsFAA = "";
$extraRdsFAA = $ARGV[5] if (@ARGV > 5);#FAA with proteins corresponding to  $extraRdsFNA
#die $cdhID."\n";
my $clustMMseq = 0;#mmseqs2Bin

#--------------------------------------------------------------program Paths--------------------------------------------------------------
my $cdhitBin = getProgPaths("cdhit");#/g/bork5/hildebra/bin/cd-hit-v4.6.1-2012-08-27/cd-hit
my $vsearchBin = "";#"/g/bork5/hildebra/bin/vsearch1.0/bin/vsearch-1.0.0-linux-x86_64";
my $bwt2Bin = getProgPaths("bwt2");#"/g/bork5/hildebra/bin/bowtie2-2.2.9/bowtie2";
my $samBin = getProgPaths("samtools");#"/g/bork5/hildebra/bin/samtools-1.2/samtools";
my $hmmBin3 = getProgPaths("hmmer3");#"/g/bork5/hildebra/bin/hmmer-3.0/hmm30/bin/hmmsearch";
#my $tabixBin = "/g/bork5/hildebra/bin/samtools-1.2/tabix-0.2.6/./tabix";
#my $bgzipBin = "/g/bork5/hildebra/bin/samtools-1.2/tabix-0.2.6/./bgzip";
my $mmseqs2Bin = getProgPaths("mmseqs2");
my $pigzBin = getProgPaths("pigz");

my $rareBin = getProgPaths("rare");#"/g/bork3/home/hildebra/dev/C++/rare/rare";
my $GCcalc = getProgPaths("calcGC_scr");#"perl $thisDir/secScripts/calcGC.pl";
my $sortSepScr = getProgPaths("sortSepReLen_scr");#"perl $thisDir/secScripts/sepReadLength.pl";
my $extre100Scr = getProgPaths("extre100_scr");#"perl $thisDir/helpers/extrAllE100GC.pl";
my $hmmBestHitScr = getProgPaths("hmmBestHit_scr");
my $genelengthScript = getProgPaths("genelength_scr");#= "/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/secScripts/geneLengthFasta.pl";

#die "$extre100Scr\n";
#my $thisDir = "/g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/";

#databases
my $FOAMhmm = getProgPaths("FOAMhmm_DB");#"/g/bork3/home/hildebra/DB/FUNCT/FOAM/FOAM-hmm_rel1.hmm";
my $ABresHMM = getProgPaths("ABresHMM_DB");#"/g/bork/forslund/morehmms/Resfams.hmm";


my $tmpDir = "/scratch/bork//GC/Dram/";# submaster
my $GLBtmp = "/scratch/bork/hildebra/GC/";
#$tmpDir = "/local/hildebra/GC/";# upsilon
#my $tmpDir =  "/alpha/data/hildebra/tmp/";#

#die $tmpDir."\n";
my $path2nt = "/genePred/genes.shrtHD.fna";
my $path2aa = "/genePred/proteins.shrtHD.faa";
my $path2gff = "/genePred/genes.gff";
my $path2FMGids = "ContigStats/FMG/FMGids.txt";
if ($bactGenesOnly){
	$path2nt = "/genePred/genes.bac.shrtHD.fna";
	$path2aa = "/genePred/proteins.bac.shrtHD.faa";
	$path2gff = "/genePred/genes.bac.gff";
}
#--------------------------------------------------------------program Paths--------------------------------------------------------------

my %FMGcutoffs = (COG0012=>94.8,COG0016=>95.8,COG0018=>94.2,COG0172=>94.4,COG0215=>95.4,COG0495=>96.4,COG0525=>95.3,COG0533=>93.1,COG0541=>96.1,
COG0552=>94.5,COG0048=>98.4,COG0049=>98.7,COG0052=>97.2,COG0080=>98.6,COG0081=>98,COG0085=>97,COG0087=>99,COG0088=>99,COG0090=>98.8,COG0091=>99,
COG0092=>99,COG0093=>99,COG0094=>99,COG0096=>98.6,COG0097=>98.4,COG0098=>98.7,COG0099=>98.9,COG0100=>99,COG0102=>99,COG0103=>98.4,
COG0124=>94.5,COG0184=>98.2,COG0185=>99,COG0186=>99,COG0197=>99,COG0200=>98.4,COG0201=>97.2,COG0202=>98.4,COG0256=>99,COG0522=>98.6);
#original, changes >99 to 99%
#my %FMGcutoffs = (COG0012=>94.8,COG0016=>95.8,COG0018=>94.2,COG0172=>94.4,COG0215=>95.4,COG0495=>96.4,COG0525=>95.3,COG0533=>93.1,COG0541=>96.1,
#COG0552=>94.5,COG0048=>98.4,COG0049=>98.7,COG0052=>97.2,COG0080=>98.6,COG0081=>98,COG0085=>97,COG0087=>99,COG0088=>99,COG0090=>98.8,COG0091=>99.2,
#COG0092=>99.2,COG0093=>99,COG0094=>99,COG0096=>98.6,COG0097=>98.4,COG0098=>98.7,COG0099=>98.9,COG0100=>99,COG0102=>99.1,COG0103=>98.4,
#COG0124=>94.5,COG0184=>98.2,COG0185=>99.3,COG0186=>99.3,COG0197=>99.3,COG0200=>98.4,COG0201=>97.2,COG0202=>98.4,COG0256=>99,COG0522=>98.6);

#my $logdir = $baseOut."LOGandSUB";
if ($mapF =~ m/^\??$/){
	if (-e "$baseOut/LOGandSUB/GCmaps.inf"){
		$mapF = `cat $baseOut/LOGandSUB/GCmaps.inf`;
		die "extracted mapf from $baseOut/LOGandSUB/GCmaps.inf\n does not exist:\n$mapF\n" if (!-e $mapF);
	} else {
		die "Can't find expected copy of inmap in GC outdir: $baseOut\n";
		#$mapF = "$baseOut/LOGandSUB/inmap.txt";
	}
}
my %map; my %AsGrps; my @samples;
if (-e $mapF){ #start building new gene cat
	print "MAP=".$mapF."\n";
	if (!-f $mapF){die"Could not find map file (first arg): $mapF\n";}
	#die $mapF."\n";
	my ($hr,$hr2) = readMapS($mapF,$oldNameFolders);
	%map = %{$hr};
	$baseOut = $map{outDir} if ($baseOut eq "" && exists($map{outDir} ));
	@samples = @{$map{smpl_order}};
	%AsGrps = %{$hr2};
	#die $map{outDir}."XX\n";
}

my $selfScript=Cwd::abs_path($PROGRAM_NAME);#dirname($0)."/".basename($0);
if ($baseOut eq "" ){die"no valid output dir specified\n";}
$baseOut.="/" unless ($baseOut =~ m/\/$/);
$baseOut =~ m/\/([^\/]+)\/?$/;
$tmpDir .= $1."/"; $GLBtmp.=$1."/";
my $OutD = $baseOut;#."GeneCatalog/";
system "mkdir -p $OutD" unless (-d $OutD);
#die $mapF;
my $qsubDir = $OutD."qsubsAlogs/";
system "echo \'$version\' > $OutD/version.txt";

#my $defaultsCDH =""; 
my $bucketCnt = 0; my $cnt = 0;
my @bucketDirs = ();
my $bdir = $OutD."B$bucketCnt/";#dir where to write the output files..
my $QSBoptHR = emptyQsubOpt($doSubmit,"");
$QSBoptHR->{qsubDir} = $qsubDir;

#$defaultsCDH = "-d 0 -c 0.$cdhID -g 0 -T $numCor -M ".int(($totMem+30)*1024) if (@ARGV>3);

if ($mapF eq "mergeCLs"){#was previously mergeCls.pl
	if (@ARGV < 4){die "Not enough args for geneCat-mergCLs\n";}
	if ($BIG==0){	$numCor = 24; $totMem = 40; }
	mergeClsSam($baseOut,$cdhID);
	exit(0);
} elsif($mapF eq "MGS"){ #create MGS/MGU with canopy clustering
	my $numCor2 = $numCor;
	if (@ARGV > 2){$numCor2 = $ARGV[2];}
	#die "$numCor2\n";
	canopyCluster($OutD,$tmpDir,$numCor2);
	exit(0);
}elsif ($mapF eq "specI" || $mapF eq "kraken" | $mapF eq "kaiju" ){ #tax assigns
	my $numCor2 = $numCor;
	if (@ARGV > 2){$numCor2 = $ARGV[2];}
	if ($mapF eq "kraken"){
		krakenTax($OutD,$tmpDir,$numCor2);
	}elsif($mapF eq "specI"){
		specITax($OutD,$numCor2);
	} else {
		kaijuTax($OutD,$tmpDir,$numCor2);
	}
	exit(0);
}elsif ($mapF eq "FMG_extr"){
	die "deprecated, use helpers/extrAllE100GC.pl\n";
	writeMG_COGs($OutD);
	exit(0);
} elsif($mapF eq "FOAM" || $mapF eq "ABR"){ #FOAM functional assignment
	FOAMassign($OutD,$tmpDir,$mapF);
	exit(0);
} elsif($mapF eq "FuncAssign"){ #eggNOG functional assignment
	
	if (@ARGV > 2){$numCor = $ARGV[2];}

	my $curDB_o = "VDB";#,KGM,TCDB,CZy,NOG,ABRc,ACL"; #"mp3,PTV,KGM,TCDB,CZy,NOG,ABRc,ACL"
	#my $curDB_o = "PTV";
	my @DBs = split /,/,$curDB_o;
	#die "@DBs\n";
	foreach my $curDB (@DBs){
		my $numCor2 = $numCor;
		if ($curDB eq "mp3"){$numCor2=1;}
		geneCatFunc($OutD,$tmpDir,$curDB,$numCor2);
	}
	
	
	exit(0);
} 
if ($BIG eq "protExtract"){#was previously mergeCls.pl
	if (@ARGV < 3){die "Not enough args for geneCat-protExtract\n";}
	#needs GC-info file && baseOut
	#$OutD =~ s/\/GeneCatalog//;
	#die $map{outDir}." DA\n";
	protExtract($OutD,$ARGV[3]); #baseOut
	exit(0);
}

#test if base folders even exist..
if ($justCDhit && !-e $OutD ){
	$justCDhit = 0;
}

if ($justCDhit==0){
	system ("rm -r $OutD\nmkdir -p $OutD\nmkdir -p $qsubDir\n");#mkdir -p $baseOut/globalLOGs");
	open QLOG,">$qsubDir/GeneCompleteness.txt";
	print QLOG "Smpl\tComplete\t3'_compl\t5'_compl\tIncomplete\tTotalGenes\n";
} else {
	system ("mkdir -p $OutD\nmkdir -p $qsubDir\n");
}
my @OCOMPL = (); my @O3P=(); my @O5P = (); my @OINC = (); #these arrays store complete & incomplete fasta seqs
my %allFMGs; #stores FMGs, seperated by COG subsets 

system "mkdir -p $baseOut/LOGandSUB/";

#copy maps
my @maps = split(/,/,$mapF);
my @newMaps;my $cntMaps=0;
foreach my $mm (@maps){
	system "cp $mm $OutD/LOGandSUB/map.$cntMaps.txt"; push (@newMaps,"$OutD/LOGandSUB/map.$cntMaps.txt"); $cntMaps++;
}
open O,">$OutD/LOGandSUB/GCmaps.inf"; print O join ",",@newMaps; close O;
open O,">$OutD/LOGandSUB/GCmaps.ori"; print O join ",",@maps; close O;
#die();
if ($BIG==0){	$numCor = 24; $totMem = 30; }

system "mkdir -p $bdir" unless (-d $bdir);
my $OC; my $O5; my $O3; my $OI;
if ($justCDhit && $toLclustering){
	die "shouldn't \n";
	open $OC,">$bdir/compl.fna" or die "Can't open $bdir/compl.fna\n"; 
	open $O5,">$bdir"."5Pcompl.fna";
	open $O3,">$bdir"."3Pcompl.fna";
	open $OI,">$bdir"."incompl.fna";
	print "Direct output to file\n";
}

print "Checking if all requires input files are present..\n";

my @skippedSmpls; my %uniqueSampleNames; my $doubleSmplWarnString = "";
#first check if all input is present
foreach my $smpl(@samples){
	last if ($justCDhit==1);
	my $dir2rd = $map{$smpl}{wrdir};
	$dir2rd = $map{$smpl}{prefix} if ($dir2rd eq "");
	if ($map{$smpl}{ExcludeAssem} eq "1"){next;}
	if ($dir2rd eq "" ){#very specific read dir..
		if ($map{$smpl}{SupportReads} ne ""){
			$dir2rd = "$baseOut$smpl/";	
		} else {
			die "Can;t find valid path for $smpl\n";
		}
	} 
	my $assGo = 0;
	my $cAssGrp = $map{$smpl}{AssGroup};
	$AsGrps{$cAssGrp}{CntAss} ++;	
	my $metaGD = "$dir2rd/assemblies/metag/";
	if (!-e "$metaGD/longReads.fasta.filt.sto" && !-e "$metaGD/scaffolds.fasta.filt"){$metaGD = `cat $dir2rd/assemblies/metag/assembly.txt`; chomp $metaGD;}
	my $inFMGd = "$metaGD/ContigStats/FMG/";
	if ($AsGrps{$cAssGrp}{CntAss}  >= $AsGrps{$cAssGrp}{CntAimAss} ){ $assGo = 1; $AsGrps{$cAssGrp}{CntAss}=0;}
	unless ($assGo){ next;}#print "Not last in comb assembly: ".$map{$smpl}{dir}."\n";
	if ((!-e "$metaGD/scaffolds.fasta.filt" || !-e "$metaGD/longReads.fasta.filt") && !-e "$metaGD/$path2nt"){# && -d $inFMGd){
		print "Skipping $dir2rd\n";
		die "no ass1\n $metaGD\n$dir2rd/assemblies/metag/assembly.txt\n" unless (-e "$metaGD/scaffolds.fasta.filt" && !-e "$metaGD/longReads.fasta.filt" ); 
		die "no ass2\n $$metaGD/longReads.fasta.filt\n" unless (-e "$metaGD/longReads.fasta.filt" ); 
		die "no NT\n" unless (-e "$metaGD/$path2nt");
		push(@skippedSmpls,$map{$smpl}{dir});
		next;
	}
	my $inGenesF = "$metaGD/$path2nt";
	my $inGenesGFF = "$metaGD/$path2gff";
	die "Gene predictions not present: $inGenesF\n" if (!-e $inGenesF);
	die "Gene annotations not present: $inGenesGFF\n" if (!-e $inGenesGFF);

}

print "All required input files seem to be presents.\nAdding up all reads\n";

#now really add all files together
my $JNUM= -1;
foreach my $smpl(@samples){
	$JNUM++;
	last if ($justCDhit==1);
	my $dir2rd = $map{$smpl}{wrdir};
	$dir2rd = $map{$smpl}{prefix} if ($dir2rd eq "");
	#die "\n".$smpl."X\n";
	if ($map{$smpl}{ExcludeAssem} eq "1"){next;}
	if ($dir2rd eq "" ){#very specific read dir..
		if ($map{$smpl}{SupportReads} ne ""){
			$dir2rd = "$baseOut$smpl/";	
		} else {
			die "Can;t find valid path for $smpl\n";
		}
	} 
	
	#check if mult assembly and adapt
	my $assGo = 0;
	my $cAssGrp = $map{$smpl}{AssGroup};
	$AsGrps{$cAssGrp}{CntAss} ++;	
	print $JNUM." - ".$cAssGrp."-".$AsGrps{$cAssGrp}{CntAss} .":".$AsGrps{$cAssGrp}{CntAimAss};
	if ($AsGrps{$cAssGrp}{CntAss}  >= $AsGrps{$cAssGrp}{CntAimAss} ){ $assGo = 1;}
	unless ($assGo){print "Not last in comb assembly: ".$map{$smpl}{dir}."\n"; next;}
	my $SmplName = $map{$smpl}{SmplID};
	#$dir2rd = "/g/scb/bork/hildebra/SNP/SimuL/sample-0/";
	my $metaGD = "$dir2rd/assemblies/metag/";
	if (!-e "$metaGD/longReads.fasta.filt.sto" && !-e "$metaGD/scaffolds.fasta.filt"){$metaGD = `cat $dir2rd/assemblies/metag/assembly.txt`; chomp $metaGD;}
	my $inFMGd = "$metaGD/ContigStats/FMG/";
	#print "\n$metaGD\n";
	#print "$dir2rd/assemblies/metag/scaffolds.fasta.filt\n";
	if ((!-e "$metaGD/scaffolds.fasta.filt" || !-e "$metaGD/longReads.fasta.filt") && !-e "$metaGD/$path2nt"){# && -d $inFMGd){
		print "Skipping $dir2rd\n";
		die "no ass1\n $metaGD\n$dir2rd/assemblies/metag/assembly.txt\n" unless (-e "$metaGD/scaffolds.fasta.filt" && !-e "$metaGD/longReads.fasta.filt" ); 
		die "no ass2\n $$metaGD/longReads.fasta.filt\n" unless (-e "$metaGD/longReads.fasta.filt" ); 
		die "no NT\n" unless (-e "$metaGD/$path2nt");
		push(@skippedSmpls,$map{$smpl}{dir});
		next;
	}
	#next;
	print "==== ".$dir2rd." ====\n";
	#print LOG "==== ".$dir2rd." ====\n";
	my $inGenesF = "$metaGD/$path2nt";
	my $inGenesFs = $inGenesF; $inGenesFs =~ s/\.fna$//;
	my $fnaHref = readFasta($inGenesF);
	my %fnas = %{$fnaHref}; my @scnts = (0,0,0,0,0);
	my $gffHref= readGFF("$metaGD/$path2gff");
	my %gff = %{$gffHref};
	my %curFMGs; 
	if ($doFMGseparation){
	open I, "<$metaGD/$path2FMGids" or die "cant open FMGids:\n$metaGD/$path2FMGids\n";
	my $cnt = 0;
		while (my $line = <I>){
			#MM1__C104459_L=563;_1 COG0552
			
			chomp $line; my @spl = split(/\s+/,$line);
			if ($cnt ==0 ){ 
				$spl[0] =~ m/(^.*)__C/;
				#check that samples was only used once
				if (exists($uniqueSampleNames{$1})){
					$doubleSmplWarnString .= "$dir2rd: Can't use sample names twice: $1\n";
				} else { $uniqueSampleNames{$1} = 1;}
			}
			$curFMGs{">".$spl[0]} = $spl[1];
			#die "$spl[0]\n";
			$cnt++;
		}	close I;
	}

	#split into buckets
	my $tooShrtCnt=0;
	foreach my $hd (keys %fnas){
		if (length($fnas{$hd}) <= $minGeneL){$tooShrtCnt++;next;}
		my $shrtHd = $hd ;	#$shrtHd =~ m/(\S+)\s/; $shrtHd = $1;
		#print $shrtHd."\n";
		#die $hd."\n";
		
		
		die "0xT20A found!\n$inGenesF\n" if ($hd =~ m/0xT20A/);
		
		
		
		unless (exists $gff{$shrtHd}){die "can't find gff entry for $shrtHd\n";}
		unless ($gff{$shrtHd} =~ m/;partial=(\d)(\d);/){ die "Incorrect gene format for gene $hd \n in file $inGenesF\n";}
		if (exists $curFMGs{$hd} && $doFMGseparation){
			$allFMGs{$curFMGs{$hd}}{$hd} = $fnas{$hd}; $scnts[4] ++;
		} elsif ($1==0 && $2==0){ #complete genes
			if ($toLclustering){#no length sorting
				print $OC $shrtHd."\n".$fnas{$hd}."\n";
			} else {
				push(@OCOMPL,$shrtHd."\n".$fnas{$hd}."\n"); 
			}

			$scnts[0] ++;
		} elsif ($1==0 && $2==1){ #3' complete
			if ($toLclustering){#no length sorting
				print $O3 $shrtHd."\n".$fnas{$hd}."\n";
			} else {
				push(@O3P,$shrtHd."\n".$fnas{$hd}."\n");
			}
			$scnts[1] ++;
		} elsif ($1==1 && $2==0){ #5' complete
			if ($toLclustering){#no length sorting
				print $O5 $shrtHd."\n".$fnas{$hd}."\n";
			} else {
				push(@O5P, $shrtHd."\n".$fnas{$hd}."\n");
			}
			$scnts[2] ++;
		} else { #gene fragments, just map
			if ($toLclustering){#no length sorting
				print $OI $shrtHd."\n".$fnas{$hd}."\n";
			} else {
				push(@OINC, $shrtHd."\n".$fnas{$hd}."\n");
			}
			$scnts[3] ++;
		}
	}
	my $totCnt = $scnts[0] + $scnts[1] + $scnts[2] + $scnts[3] ;
	my $ostr= "";
	if ($totCnt>0){
		$ostr= $totCnt."+$scnts[4] genes: ".sprintf("%.3f",($scnts[0]/$totCnt*100)). "% complete, ";
		$ostr.=sprintf("%.1f",$scnts[1]/$totCnt*100)."% 3' compl, ";
		$ostr.=sprintf("%.1f",$scnts[2]/$totCnt*100). "% 5' compl, ";
		$ostr.=sprintf("%.1f",$scnts[3]/$totCnt*100). "% incompl, ";
		$ostr.=sprintf("%.1f",$tooShrtCnt). " < $minGeneL";
		
	} else {
		$ostr = "0 genes found.\n";
	}
	print $ostr."\n"; 
	print QLOG "$SmplName\t$scnts[0]\t$scnts[1]\t$scnts[2]\t$scnts[3]\t$totCnt\t$tooShrtCnt\n";
	$cnt++;
	if ( 0 && $cnt % 10 == 0) {#write out & submit cdhit job
		my $bdir = $OutD."B$bucketCnt/";
		writeBucket(\@OCOMPL,\@O3P,\@O5P,\@OINC,$bdir,$bucketCnt);
		$bucketCnt++;
		push(@bucketDirs,$bdir);
		#clean old seqs
		@OCOMPL=();@O3P=();@O5P=();@OINC=();
		#die () if ($bucketCnt ==2);
	}
	if ($doubleSmplWarnString ne ""){
		die $doubleSmplWarnString."\n";
	}
	#last;
}


#any extra reads (e.g. from ref genomes?)


if ($justCDhit==0 && $extraRdsFNA ne ""){
	my $fnaHref = readFasta($extraRdsFNA);
	my %fnas = %{$fnaHref}; 
	my $xcnts = 0; my $tooShrtCnt=0;
	foreach my $hd (keys %fnas){
		if (length($fnas{$hd}) <= $minGeneL){$tooShrtCnt++;next;}
		my $shrtHd = $hd ;	$shrtHd =~ m/(\S+)\s/; $shrtHd = $1;
		#
		#just assume that every gene is complete
		if ($toLclustering){#no length sorting
			print $OC $shrtHd."\n".$fnas{$hd}."\n";
		} else {
			push(@OCOMPL,$shrtHd."\n".$fnas{$hd}."\n"); 
		}
		$xcnts ++;
	}
	print "Added $xcnts genes from external source\nSkipped $tooShrtCnt Genes (too short $minGeneL)\n";
	print QLOG "Added $xcnts genes from external source\n";
}

#die();
print "\n\n--skipped: ".join(",",@skippedSmpls)."\n" if (@skippedSmpls > 0);
my %FMGfileList;
if ($justCDhit==0){
	writeBucket(\@OCOMPL,\@O3P,\@O5P,\@OINC,$bdir,$bucketCnt);
	#write marker genes separate
	foreach my $cog (keys (%allFMGs)){
		system "mkdir -p $bdir/COG/" unless (-d "$bdir/COG/");
		my %cogFMG = %{$allFMGs{$cog}};
		my $ccogf = "$bdir/COG/preclus.$cog.fna";
		open Ox,">$ccogf" or die "Can't open COG output file $ccogf\n";
		$FMGfileList{$cog} =  "$ccogf";
		foreach my $geK (sort { length($cogFMG{$a}) <=> length($cogFMG{$b}) } keys %cogFMG) {
			print Ox $geK."\n".$cogFMG{$geK}."\n";
		}
		close Ox;
	}
} elsif (-d "$bdir/COG") { #COGs were created
	opendir(DIR, "$bdir/COG/") or die $!;
	my @cogfiles = grep {/^COG\d+\.preclus\.fna$/ && -f "$bdir/COG/$_" } readdir(DIR); close DIR;
	for (my $i=0; $i<@cogfiles; $i++){
		$cogfiles[$i] =~ m/(^COG\d+)\.preclus\.fna$/;
		$FMGfileList{$1} = "$bdir/COG/".$cogfiles[$i] unless (-e "$bdir/$1.fna.clstr");
	}
}

#big step
submCDHIT($bdir,$bucketCnt,$OutD,$map{outDir},\%FMGfileList);#,$baseOut);
if ($justCDhit==0){	close QLOG;}
if ($toLclustering){#no length sorting, just write directly
	close $O3;close $OC;close $O5; close $OI;
}

print "FInished\n";
exit(0);
#####################################################################
#####################################################################

sub krakenTax{
	my ($GCd,$tmpD,$NC) = @_;
	my $krkBin = getProgPaths("kraken");#"/g/scb/bork/hildebra/DB/kraken/./kraken";
	my $oriKrakDir = getProgPaths("Kraken_path_DB");
	my $outD = $GCd."/Anno/Tax/";
	system "mkdir -p $outD" unless (-d $outD);
	system "mkdir -p $tmpD" unless (-d $tmpD);
	my @thrs = (0.01,0.02,0.04,0.06,0.1,0.2,0.3);
	my $geneFNA = "$GCd/compl.incompl.95.fna";
	my $curDB = "$oriKrakDir/minikraken_2015";
	#die $curDB."\n";
	#paired read tax assign
	my $cmd .= "$krkBin --preload --threads $NC --fasta-input  --db $curDB  $geneFNA >$tmpD/rawKrak.out\n";
	for (my $j=0;$j< @thrs;$j++){
		$cmd .= "$krkBin-filter --db $curDB  --threshold $thrs[$j] $tmpD/rawKrak.out | $krkBin-translate --mpa-format --db $curDB > $outD/krak_$thrs[$j]".".out\n";
	}
	print "Starting kraken assignments of the gene catalog\n";
	systemW $cmd unless (-e "$outD/krak_0.1.out");
	print "All kraken assignments are done\n";
	for (my $j=0;$j< @thrs;$j++){
		open I,"<$outD/krak_$thrs[$j].out" or die "could not find file $outD/krak_$thrs[$j].out";
		open O,">$outD/krak_$thrs[$j].txt" or die "could not open file $outD/krak_$thrs[$j].txt";
		while(<I>){
			chomp;
			s/\|/;/g;
			print O $_."\n";
		}
		close I;close O;
	}	
	$cmd = "$rareBin sumMat -i $GCd/Matrix.mat -o $outD/krak_$thrs[0].mat -refD $outD/krak_$thrs[0].txt\n";
	systemW $cmd;
}
sub specITax{
	my ($GCd,$nc) = @_;
	my $siScr = getProgPaths("specIGC_scr");
	my $cmd = "$siScr $GCd $nc\n";
	print "Calculating tax abundance via SpecI's\n";
	systemW $cmd;
}
sub kaijuTax{#different tax assignment for gene catalog
	my ($GCd,$tmpD,$NC) = @_;
	my $kaijD = getProgPaths("kaijuDir");
	my $kaijBin = "$kaijD/./kaiju";
	my $KaDir = getProgPaths("Kaiju_path_DB");
	my $outD = $GCd."/Anno/Tax/";
	system "mkdir -p $outD" unless (-d $outD);
	system "mkdir -p $tmpD" unless (-d $tmpD);
	my @thrs = (0.01,0.02,0.04,0.06,0.1,0.2,0.3);
	my $geneFNA = "$GCd/compl.incompl.95.fna";
	#die $curDB."\n";
	#paired read tax assign
	my $kaDB = "-t $KaDir/nodes.dmp -f $KaDir/kaiju_db.fmi";
	my $cmd .= "$kaijBin $kaDB -z $NC -i  $geneFNA -o $tmpD/rawKaiju.out\n";
	$kaDB = "-t $KaDir/nodes.dmp -n $KaDir/names.dmp";
	$cmd .= "$kaijD/./addTaxonNames $kaDB -i $tmpD/rawKaiju.out -o $tmpD/Kaiju1.anno -u -p \n";
	$cmd .= "sort $tmpD/Kaiju1.anno > $outD/Kaiju.anno\n";
	print "Starting kaiju assignments of the gene catalog\n";
	systemW $cmd;
	print "All kaiju assignments are done\n";
}
sub canopyCluster{
	my ($GCd,$tmpD,$NC) = @_;
	my $canBin = "/g/bork3/home/hildebra/bin/canclus/cc_x64.bin";
	my $matF_pre = "$GCd/Matrix.mat";
	my $matF = "$GCd/Matrix.norm.mat";
	my $cmd = "";
	unless (-e $matF){
		print "Normalizing GC matrix.\n";
		$cmd .= "$rareBin normalize -i $matF_pre -o $matF\n";
		#print "Done\n";
	}
	my $oD = "$GCd/Canopy/";	system "rm -r $oD;mkdir -p $oD";
	my $jdeps = "";
	#die "Can't find matrix infile $matF\n" unless (-e $matF);
	$cmd .= "$canBin -i $matF -o $oD/clusters.txt -c $oD/profiles.txt -p TC -n $NC --die_on_kill --stop_criteria 250000 --cag_filter_min_sample_obs 5 --cag_filter_max_top3_sample_contribution 1 --filter_max_top3_sample_contribution 1\n";
#	print $cmd 
	#my ($jdep,$txtBSUB) = qsubSystem($qsubDir."CanopyCL.sh",$cmd,$numCPU,"4G","CAN",$jdeps,"",1,[],$QSBoptHR);print "MGS call send off\n"; 
	
	#die $cmd."\n";
	if (system $cmd){
		print $cmd."\n";
	}
	print "Finished Canopy clustering.\n";
	
	exit(0);
}

sub nt2aa(){#takes gene cluster fna and collects respective AA from file
#probably better done with my C program
}

sub cleanUpGC(){#not used any longer
	my ($bdir,$fdir,$cdhID) = @_;
}



sub protExtract{
	my ($inD,$protXtrF) =@_;
	#gets the AA seqs for each "master" protein
	#1 read 
	#die keys %map;
	
	my $protF = $inD."compl.incompl.95.prot.faa";
	#my $incl = $inD."Matrix.genes2rows.txt";
	system("rm -f $protF");
	print "Writing to new proteins file: \n$protF\n";
	
	my ($geneIdxH,$numGenes) = readGeneIdx($inD."Matrix.genes2rows.txt");
	rewriteFastaHdIdx($inD."compl.incompl.95.fna",$geneIdxH);
	
	
	my %linV = %{$geneIdxH}; #represent gene name to matrix ID
	my @ordG = sort keys %linV;
	#temp DEBUG
	#my @ordG = ('Va48.6M6__C64835_L=218572=_153');
	if (@ordG != $numGenes){ die "NUmber of genes read not equal to actual number of genes. Not enough mem?\n";}
	my $curSmpl=""; my $ctchStr = ""; my $cnt=0; 
	my @ctchAr=();
	my $ctchStrXtr = "";
	print "Starting Protein Extraction from source assembly folders\n";
	#collects all genes from a given sample, that is serving as seed gene for clustering
	for my $k (@ordG){
		my @spl = split(/__/, $k);
		#print "$k\n";
		if (@spl == 1){#this is an extra protein
			#die "@spl\n";
			$ctchStrXtr .= "'$k' ";
			next; #$cnt ++; 
		}
		if ($curSmpl ne $spl[0]){ #this part writes all protein IDs collected for current sample to tmp file
			#use faidx to extract all collected gene IDs for current sample
			if ($curSmpl eq ""){
				$curSmpl = $spl[0]; 
			} else {
				unless (exists ($map{$curSmpl})){$curSmpl = $map{altNms}{$curSmpl} if (exists ($map{altNms}{$curSmpl}));}
				unless (exists ($map{$curSmpl})){#also extra protein, but with __ marker in them
					print "sk_ $curSmpl\n"; $ctchStrXtr .= $ctchStr; $ctchStr="";$curSmpl="";next;
				}
				print $curSmpl." $cnt\n";
				#if (!exists($map{$curSmpl}) || !exists($map{$curSmpl}{wrdir}) ){die "$curSmpl not in mapping file\n";}
				my $metaGD = "$map{$curSmpl}{wrdir}/assemblies/metag/";
				my $protIn = $metaGD."/".$path2aa;
				if ( -e "$metaGD/assembly.txt"){
					$metaGD = `cat $metaGD/assembly.txt`; chomp $metaGD;
					$protIn = $metaGD."/".$path2aa;
				}
#				my $metaGD = `cat $map{$curSmpl}{wrdir}/assemblies/metag/assembly.txt`; chomp $metaGD;
#				my $protIn = $metaGD."/".$path2aa;
				#unless (-e $protIn){$protIn = $map{$curSmpl}{wrdir}."/"."assemblies/metag/genePred/proteins.faa.shrtHD.faa";}
				die "prot file $protIn doesnt exits\n" unless (-e $protIn);
				#open O,">$inD/tmp.txt";print O $ctchStr;close O;
				#attachProteins("$inD/tmp.txt",$protF,$protIn,$geneIdxH);
				attachProteins2(\@ctchAr,$protF,$protIn,$geneIdxH);
				#systemW("cat $basD/tmp.txt | xargs samtools faidx $protIn  >> $protF");
				#print $k."\n";
				#die $protIn."\n";
				$curSmpl = $spl[0];$ctchStr="";@ctchAr=();
				#print $curSmpl."\n";
			}
		}
		#$ctchStr.="'$k' ";
		push(@ctchAr,$k);
		$cnt++;
		#die "$ctchStr\n" if ($cnt == 10);
	}
	#last round
	unless (exists ($map{$curSmpl})){$curSmpl = $map{altNms}{$curSmpl} if (exists ($map{altNms}{$curSmpl}));}
	unless (exists ($map{$curSmpl})){$ctchStrXtr .= $ctchStr; #prob extra protein
	}else{	
		my $metaGD = "$map{$curSmpl}{wrdir}/assemblies/metag/";
		my $protIn = $metaGD."/".$path2aa;
		if ( -e "$metaGD/assembly.txt"){
			$metaGD = `cat $metaGD/assembly.txt`; chomp $metaGD;
			$protIn = $metaGD."/".$path2aa;
		}
#		my $metaGD = `cat $map{$curSmpl}{wrdir}/assemblies/metag/assembly.txt`; chomp $metaGD;
#		my $protIn = $metaGD."/".$path2aa;
#		open O,">$inD/tmp.txt";print O $ctchStr;close O;
#		attachProteins("$inD/tmp.txt",$protF,$protIn,$geneIdxH);
		attachProteins2(\@ctchAr,$protF,$protIn,$geneIdxH);
	}
	
	unlink "$inD/tmp.txt";
	print "rewritten $cnt proteins, expected $numGenes\n";
	
	#extra added proteins (not from MATAFILER assembly)
	if ($protXtrF ne ""){
		open O,">$inD/tmp.txt";print O $ctchStrXtr;close O;
		#die ("extra\n$inD/tmp.txt\n");
		attachProteins("$inD/tmp.txt",$protF,$protXtrF,$geneIdxH);
	}

	#new cluster numbers and one file with Idx
	combineClstr("$inD/compl.incompl.95.fna.clstr","$inD/Matrix.genes2rows.txt") ;

}
sub combineClstr(){
	my ($clstr,$idx) = @_;
	#currently can only be run first time!
	print "Combining cluster strings.. \n";
	#tmp out files, copied over to correct locations later!
	open I,"<$clstr"; open O,">$clstr.2"; open Oi,">$clstr.idx2"; open C,"<$idx"; 
	my $chLine = <C>; my $newOil=0;
	#counts if already formated?
	my $evidence=0; my $eviNo=0;
	my $oil = ""; #collects for current cluster genes
	print Oi "#Gene	members\n";
	while (my $line = <I>){
		chomp $line;
		if ($line =~ m/^>/){
			$line =~ m/^>(.*)/;
			#chop $oil;
			print Oi $oil."\n" if ($oil ne "");
			$chLine = <C>;
			
			my @spl = split(/\t/,$chLine);
			if ($1 eq $spl[0]){
				$evidence++;
				if ($evidence>10 && $eviNo == 0){
					print "It seems like index file was already created, aborting coversion..\n";
					systemW "rm $clstr.idx2 $clstr.2";
					return;
				}
			} else {
				$eviNo ++;
			}
			if ($spl[1] ne $line){
				die "Can;t match \n$line \n$spl[1]\n";
			}
			
			$line = ">$spl[0]";
			$oil = $spl[0]."\t";
			$newOil = 1;
			#die "FND :: $line\n";
		} else {
			$line =~ m/\s+(>.*)\.\.\.\s.*/;
			if ($newOil){
				$oil.=$1;
				$newOil=0;
			} else {
				$oil.=",".$1;
			}
		}
		print O $line."\n";
	}
	#insert last entry
	print Oi $oil."\n";
	systemW "rm $clstr; mv $clstr.2 $clstr";
	systemW "rm $clstr.idx" if (-e "$clstr.idx");
	systemW "mv $clstr.idx2 $clstr.idx";
	print "Done rewriting cluster numbers & creating cluster index\n";
	close I; close O;close C; close Oi;
}


sub clusterFNA($ $ $ $ $ $ $){
	my ($inFNA, $oFNA, $aS,$aL, $ID, $numCor, $gfac) = @_;
	my $cmd = "";
	if ($ID >1){$ID=$ID/100;}
	if ($clustMMseq){#mmseq2 clustering
		$cmd .= $mmseqs2Bin;
	} else {
		#	$defaultsCDH = "-d 0 -c 0.$cdhID -g 0 -T $numCor -M ".int(($totMem+30)*1024) if (@ARGV>3);
		$cmd .= $cdhitBin."-est -i $inFNA -o $oFNA -n 9 -G 1 -r 1 -aS $aS -aL $aL -d 0 -c $ID -g $gfac -T $numCor -M ".int(($totMem+30)*1024)."\n";
	}
	return $cmd;
}

sub submCDHIT($ $ $ $ $){
	my ($bdir,$nm,$OutD,$assDirs,$hr) = @_;
	my $cmd = "";
	#-G global alignment score -s overlap % -g [1:complete search to best cluster hit]
	#complete genes
	my %FMGfileList = %{$hr};
	$cmd .= "rm -rf $tmpDir\nmkdir -p $tmpDir\n";
	my $copycat=0;
	
	#cluster FMGs
	my %FMGFL2 ; my $dirflag=0; my $cpFromP = 0;
	my @COGlst = keys %FMGfileList;
	foreach my $cog ( @COGlst){
		die "can't find $cog in FMGcutoffs list\n" unless (exists $FMGcutoffs{$cog});
		$cmd .= "mkdir -p $tmpDir/COG/\n" unless ($dirflag);$dirflag=1;
		if (!-s "$bdir/COG/$cog.$cdhID.fna"){
			$copycat = 1;
			#$cmd .= $cdhitBin."-est -i $FMGfileList{$cog} -o $tmpDir/COG/$cog.$cdhID.fna -n 9 -G 1 -aS 0.95 -aL 0.6 -d 0 -c ". $FMGcutoffs{$cog}/100 ." -g 0 -T $numCor\n";
			$cmd .= clusterFNA($FMGfileList{$cog},"$tmpDir/COG/$cog.$cdhID.fna",0.95,0.6,($FMGcutoffs{$cog}/100),$numCor,1);
			$FMGFL2{$cog} = "$tmpDir/COG/$cog.$cdhID.fna";
		} else {
			$cpFromP = 1;
			#$cmd .= "cp $bdir/COG/$cog.$cdhID.fna* $tmpDir/COG/;"; 
		}
	}
	if ($cpFromP){
		$cmd .= "cp $bdir/COG/COG*.$cdhID.fna* $tmpDir/COG/;"; 
	}
	if ($copycat){
		$cmd .=  "cp $tmpDir/COG/COG*.$cdhID.fna* $bdir/COG\n";
	}
	$cmd .= "\n";
	$copycat = 0;
	if (1){
		if ((-s "$bdir/compl.$cdhID.fna" && -s "$bdir/compl.$cdhID.fna.clstr") || (-s "$bdir/compl.$cdhID.fna.gz" || -s "$bdir/compl.$cdhID.fna.clstr.gz")){
		#-s 0.8
			$cmd .= "cp $bdir/compl.$cdhID.fna* $tmpDir\n"; $copycat=1;
			$cmd .= "gunzip $tmpDir/compl.$cdhID.fna*\n" if (-s "$bdir/compl.$cdhID.fna.gz" || -s "$bdir/compl.$cdhID.fna.clstr.gz");
		} else {
			#$cmd .= $cdhitBin."-est -i $bdir/compl.fna -o $tmpDir/compl.$cdhID.fna  -n 9 -G 1 -aS 0.95 -aL 0.6 $defaultsCDH \n" ;
			$cmd .= clusterFNA( "$bdir/compl.fna", "$tmpDir/compl.$cdhID.fna",0.95,0.6,"$cdhID",$numCor,0);
			$cmd .= "cp $tmpDir/compl.$cdhID.fna* $bdir\n" unless ($copycat);
		}
	} else {
		$cmd .= "gunzip $bdir/compl.fna.gz\n" if (-e "$bdir/compl.fna.gz" && !-e "$bdir/compl.fna");
		$cmd .= $vsearchBin." --cluster_fast $bdir/compl.fna --consout $tmpDir/compl.$cdhID.fna --id 0.$cdhID --strand plus --threads $numCor --uc $tmpDir/compl.$cdhID.uc";
	}
	#5', 3' complete genes and incompletes
	my $REF = "$tmpDir/compl.$cdhID.fna";
	
	$copycat=0;
	
	if (0){ #too fucking slow
		#$cmd .= $cdhitBin."-est-2d -i $ref -i2 $bdir/5Pcompl.fna -o $bdir/5Pcompl.$cdhID.fna -n 9 -G 0 -M 5000 -aL 0.5 -aS 0.95 $defaultsCDH\n";
		#$cmd .= $cdhitBin."-est-2d -i $REF -i2 $bdir/3Pcompl.fna -o $bdir/3Pcompl.$cdhID.fna -n 9 -G 0 -M 5000 -aL 0.5 -aS 0.95 $defaultsCDH\n";
		#$cmd .= $cdhitBin."-est-2d -i $REF -i2 $bdir/incompl.fna -o $bdir/incompl.$cdhID.fna -n 9 -G 0 -M 5000 -aL 0.3 -aS 0.95 $defaultsCDH\n";
	} elsif (1) { #mem scales to core number (linear!)
		my $bwtIdx = $REF.".bw2";
		my $bwtIncLog = "$qsubDir/bowTie_incompl.log"; my $bwt35Log = "$qsubDir/bowTie_35.log";
		my $bwtIdxB0 = "$bdir/SAM/compl.$cdhID.fna.bw2";
		system "mkdir -p $bdir/SAM";
		
		my $bwtCore = $numCor;
		#$bwtCore=16;# if ($bwtCore > 25);
		
		#build bowtie index?
		if ( !-s "$bdir/SAM/35compl.$cdhID.align.sam"  || !-s "$bdir/SAM/P35compl.NAl.pre.$cdhID.fna" || 
				!-s "$bdir/SAM/incompl.$cdhID.align.sam" || !-s "$bdir/SAM/incompl.NAl.pre.$cdhID.fna" ){
			unless (-e $bwtIdxB0.".rev.2.bt2" && -e $bwtIdxB0.".4.bt2"&& -e $bwtIdxB0.".2.bt2"){
				$cmd .= $bwt2Bin."-build --threads $bwtCore -q $REF $bwtIdx\n" ;
			} else {
				$cmd .= "cp $bwtIdxB0* $tmpDir\n";
			}
		}
		#p35 incomplete genes
		if ( !-s "$bdir/SAM/35compl.$cdhID.align.sam"  || !-s "$bdir/SAM/P35compl.NAl.pre.$cdhID.fna"){
			if (-e "$bdir/5Pcompl.fna.gz" && !-e "$bdir/5Pcompl.fna"){
				$cmd .= "zcat $bdir/5Pcompl.fna.gz > $tmpDir/35Pcompl.fna\n" 
			} else {
				$cmd .= "cat $bdir/5Pcompl.fna > $tmpDir/35Pcompl.fna\n";#>> $bdir/incompl.fna \n";
			}
			if (-e "$bdir/3Pcompl.fna.gz" && !-e "$bdir/3Pcompl.fna"){
				$cmd .= "zcat $bdir/3Pcompl.fna.gz >> $tmpDir/35Pcompl.fna\n\n";
			} else {
				$cmd .= "cat $bdir/3Pcompl.fna >> $tmpDir/35Pcompl.fna\n\n";
			}
			
			#take care of long reads
			$cmd .= "$sortSepScr 8000 $tmpDir/35Pcompl.fna\n";
			$cmd .= $bwt2Bin." --sensitive --local --norc --no-unal --no-hd --no-sq -p 1 ";
			$cmd .= "--un $tmpDir/P35compl.NAl.pre.$cdhID.fna.long -x $bwtIdx -f -U  $tmpDir/35Pcompl.fna.long > $tmpDir/35compl.$cdhID.align.sam 2> $bwt35Log\n";
			#and bulk of reads
			$cmd .= $bwt2Bin." --sensitive --local --norc --no-unal --no-hd --no-sq -p $bwtCore ";
			$cmd .= "--un $tmpDir/P35compl.NAl.pre.$cdhID.fna -x $bwtIdx -f -U  $tmpDir/35Pcompl.fna >> $tmpDir/35compl.$cdhID.align.sam 2>> $bwt35Log\n";
			
			#fix missing newlines
			$cmd .= "cat $tmpDir/P35compl.NAl.pre.$cdhID.fna.long >> $tmpDir/P35compl.NAl.pre.$cdhID.fna\n rm $tmpDir/P35compl.NAl.pre.$cdhID.fna.long\n";
			$cmd .= "\nsed -i -r 's/([ACGT])>/\\1\\n>/g' $tmpDir/P35compl.NAl.pre.$cdhID.fna\n";

			$cmd .= "cp $tmpDir/P35compl.NAl.pre.$cdhID.fna $tmpDir/35compl.$cdhID.align.sam $bdir/SAM/\n" ;
			
			#$bwtCore=50 if ($bwtCore > 50);
		 } else {
			$cmd .= "cp $bdir/SAM/35compl*.sam  $bdir/SAM/P35compl.NAl.pre.$cdhID.fna $tmpDir/\n";
		 }
		if (!-s "$bdir/SAM/incompl.$cdhID.align.sam" || !-s "$bdir/SAM/incompl.NAl.pre.$cdhID.fna"  ){
			if (-e "$bdir/incompl.fna.gz" && !-e "$bdir/incompl.fna"){
				$cmd .= "gunzip $bdir/incompl.fna.gz\n";
			}
			#take care of long reads
			$cmd .= "$sortSepScr 8000 $bdir/incompl.fna\n";

			$cmd .= $bwt2Bin." --sensitive --local --norc --no-unal --no-hd --no-sq -p 1 ";
			$cmd .= "--un $tmpDir/incompl.NAl.pre.$cdhID.fna.long -x $bwtIdx -f -U $bdir/incompl.fna.long > $tmpDir/incompl.$cdhID.align.sam 2> $bwtIncLog\n";
			$cmd .= $bwt2Bin." --sensitive --local --norc --no-unal --no-hd --no-sq -p $bwtCore ";
			$cmd .= "--un $tmpDir/incompl.NAl.pre.$cdhID.fna -x $bwtIdx -f -U $bdir/incompl.fna >> $tmpDir/incompl.$cdhID.align.sam 2>> $bwtIncLog\n";
			$cmd .= "cat $tmpDir/incompl.NAl.pre.$cdhID.fna.long >> $tmpDir/incompl.NAl.pre.$cdhID.fna\n rm $tmpDir/incompl.NAl.pre.$cdhID.fna.long\n";
			$cmd .= "sed -i -r 's/([ACGT])>/\\1\\n>/g' $tmpDir/incompl.NAl.pre.$cdhID.fna\n";
			$cmd .= "cp $tmpDir/incompl.NAl.pre.$cdhID.fna $tmpDir/incompl.$cdhID.align.sam $bdir/SAM/\n" ;
		 } else {
			$cmd .= "cp $bdir/SAM/incompl*.sam  $bdir/SAM/incompl.NAl.pre.$cdhID.fna $tmpDir/\n";
		 }
	} else {
		$cmd .= "blat -out=blast8 -extendThroughN -minIdentity=95 -t=dna -q=dna "
	}
	#from now on all single core jobs..
	#merge cluster track files (as they all match to same ref DB set)
	#$cmd .= "rm -f $bwtIdx"."*\n"; #<- leave in
	$cmd .= "perl $selfScript mergeCLs $tmpDir $BIG $cdhID\n";
	#$cmd .= "cp $tmpDir/compl.incompl.$cdhID.fna* $bdir\n";

	$cmd .= "cp $tmpDir/cluster.ids* $OutD\n";
	#remove blank lines..
	$cmd .= "\nsed '/^\$/d' $tmpDir/compl.incompl.$cdhID.fna > $tmpDir/compl.incompl.$cdhID.fna.tmp;rm $tmpDir/compl.incompl.$cdhID.fna;mv $tmpDir/compl.incompl.$cdhID.fna.tmp $tmpDir/compl.incompl.$cdhID.fna\n";

	#calc gene matrix.. can as well be run later on finished file..
	if (1||$doGeneMatrix){
		my $newMapp = ""; $newMapp = "-oldMapStyle" if ($oldNameFolders);
		$cmd .= "$rareBin geneMat -i $tmpDir/compl.incompl.$cdhID.fna.clstr -o $OutD/Matrix $newMapp -map $mapF -refD $assDirs\n"; #add flag -useCoverage to get coverage estimates instead
		$cmd .= "$rareBin geneMat -i $tmpDir/compl.incompl.$cdhID.fna.clstr -o $OutD/Mat.cov $newMapp -map $mapF -refD $assDirs -useCoverage\n"; #coverage mat
		$cmd .= "$pigzBin -p $numCor $OutD/Mat.cov* \n";
	}
	
	$cmd .= "$GCcalc $tmpDir/compl.incompl.$cdhID.fna $tmpDir/compl.incompl.$cdhID.fna.GC\n";
	$cmd .= "$genelengthScript $tmpDir/compl.incompl.$cdhID.fna $tmpDir/compl.incompl.$cdhID.fna.length\n";

	#move to final location
	$cmd .= "mv $tmpDir/compl.incompl.$cdhID.fna* $OutD\n";
	
	$cmd .= "mkdir -p $qsubDir/FMG\ncp $tmpDir/COG/*.fna.clstr $tmpDir/FMGclusN.log $qsubDir/FMG\n" if (@COGlst > 0);

	#get protein sequences for each gene & rewrite seq names to numbers
	$cmd .= "perl $selfScript ? $baseOut protExtract \"$extraRdsFAA\"\n";
	$cmd .= "$extre100Scr $OutD $oldNameFolders\n";
	$cmd .= "$selfScript MGS $OutD\n";
	$cmd .= "$selfScript kraken $OutD\n";
	#$cmd .= "$selfScript kaiju $OutD\n"; #kaiju is too instable.. don't use
	$cmd .= "$selfScript specI $OutD\n";
	
	
	$cmd .= "mv $tmpDir/log/Cluster.log $qsubDir\n";
	#$cmd .= cleanUpGC($bdir,$OutD,$cdhID);
	$cmd .= "rm -f $bdir/SAM/compl.$cdhID.fna.bw2*\n";
	#cp relevant files to outdir and zip the rest
	$cmd .= "$pigzBin -p $numCor $bdir/*\n";
	$cmd .= "rm -f -r $tmpDir\n";
	#add gc calcs
	#these incompletes have to be added to big gene catalog in last step by themselves (avoid mis-center clustering

	#tabix prep of matrix
	#tabix doesn't work properly.. use sed idx'ing instead
	#$cmd.= "$bgzipBin $OutD/Matrix.mat\n" ;
	#$cmd.= "$tabixBin -S 1 -s 1 $OutD/Matrix.mat.gz\n";
	#die $cmd."\n";

	my $jobName = "CD_$nm";
	


	my $jobd = "";
	print $qsubDir."CDHITexe.sh\n";
	my ($dep,$qcmd) = qsubSystem($qsubDir."CDHITexe.sh",$cmd,$numCor,int($totMem/$numCor)."G",$jobName,$jobd,"",$qsubNow,[],$QSBoptHR);
	if ($qsubNow==0){
		print "$qcmd\n";
	}
	#die ($cmd);
}
sub writeBucket(){
	my ($OCOMPLar,$O3Par,$O5Par,$OINCar,$bdir,$bnum) = @_;
	if ($toLclustering){return;}
	systemW("mkdir -p $bdir");
	#my @OCOMPL = @{$OCOMPLar}; 
	if (@{$OCOMPLar} ==0){die "no genes found!";}
	if ($toLclustering){#no length sorting
		#open O,">$bdir"."compl.fna"; foreach( @OCOMPL ){print O $_;} close O;
		#open O,">$bdir"."5Pcompl.fna"; foreach( @O3P ){print O $_;} close O;
		#open O,">$bdir"."3Pcompl.fna"; foreach( @O5P ){print O $_;} close O;
		#open O,">$bdir"."incompl.fna";foreach( @OINC ){print O $_;} close O;
	} else {
		open O,">$bdir"."compl.fna" or die "Can't open B0 compl.fna\n"; 
		foreach(sort {length $b <=> length $a} @{$OCOMPLar} ){print O $_;} close O; @{$OCOMPLar} = ();
		my @O5P = @{$O5Par};
		open O,">$bdir"."5Pcompl.fna" or die "Can't open B0 5P.fna\n"; foreach(sort {length $b <=> length $a} @O5P ){print O $_;} close O; @O5P=();
		my @O3P = @{$O3Par};  
		open O,">$bdir"."3Pcompl.fna" or die "Can't open B0 3P.fna\n"; foreach(sort {length $b <=> length $a} @O3P ){print O $_;} close O; @O3P=();
		 my @OINC = @{$OINCar}; 
		open O,">$bdir"."incompl.fna" or die "Can't open B0 incompl.fna\n";foreach(sort {length $b <=> length $a} @OINC ){print O $_;} close O;  @OINC=();
	}
}
sub readFasta($){
  my ($fil) = @_;
  my %Hseq;
  if (-z $fil){ return \%Hseq;}
  open(FAS,"<","$fil") || die("Couldn't open FASTA file $fil.");
    
     my $temp; 
     my $line; my $hea=<FAS>; chomp ($hea);
      my $trHe = ($hea);
      #my @tmp = split(" ",$trHe);
      #$trHe = substr($tmp[0],1);
      # get sequence
    while($line = <FAS>)
    {
      #next if($line =~ m/^;/);
      if ($line =~ m/^>/){
        chomp($line);
        $Hseq{$trHe} = $temp;
        $trHe = ($line);
       # @tmp = split(" ",$trHe);
		#$trHe = substr($tmp[0],1);
		$trHe =~ s/\|//g;
        $temp = "";
        next;
      }
    chomp($line);
    $line =~ s/\s//g;
    $temp .= ($line);
    }
    $Hseq{$trHe} = $temp;
  close (FAS);
    return \%Hseq;
}
sub rewriteClusNumbers($ $ ){
	my ($infna,$newCnt) = @_;
	print "Rewriting Cluster numbers: $newCnt in $infna.clstr\n";
	my $incls = $infna.".clstr";
	my $ocls = $infna.".clstr.new";
	my $mem = 0;
	open I,"<$incls" or die "RewriteClusNum: Can't open i $incls\n";
	open O,">$ocls" or die "RewriteClusNum: Can't open o $ocls\n";
	while(my $line = <I>){
		if ($line =~ m/^>Cluster/){
			$newCnt++;
			#>Cluster 0
			#$line =~ s/>Cluster \d/>Cluster 0/;
			print O ">Cluster $newCnt\n";
		} else {
			$mem++;
			print O $line;
		}
	}
	close I; close O;
	systemW("rm -f $incls\nmv $ocls $incls \n");
	return($newCnt,$mem);
}
sub writeIDs($ $){
	my ($hr, $of) = @_;
	my %ids = %{$hr};
	open O,">$of" or die "can't open $of cluster id file\n";
	foreach my $k (keys %ids){
		print O $k."\t".$ids{$k}."\n";
	}
	close O;
}

sub mergeClsSam(){
	my ($inD,$idP) = @_;
	my $samF = $inD."incompl.$idP.align.sam";
	my $samF2 = $inD."35compl.$idP.align.sam";
	my $completeFNA = $inD."compl.$idP.fna";

	my $outFfna = $inD."compl.incompl.$idP.fna";
	#die "$outFfna\n";
	my $outFcls = $outFfna.".clstr";
	my $clFile = $completeFNA.".clstr";
	#system "cp $clFile $clFile.before"; #TODO, remove
	my $logf = "$inD/log/Cluster.log";
	systemW("mkdir -p $inD/log/");
	open LOG,">$logf";
	my ($hr1,$hr2,$totN,$totM,$idsHr) = readCDHITCls($clFile);
	print LOG "ComplGeneClus	$totN\nComplGeneClusMember	$totM\n";
	my %lnk  = %{$hr2};
	my %cls = %{$hr1};
	my %idsDistr = %{$idsHr};
	writeIDs($idsHr,"$inD/cluster.ids.primary");
	my %Hitin; my $remSeqs;
	my $totCnt = 0;
	for (my $k=0;$k<2;$k++){
		if ($k==0){
			#my $fref = readFasta("$inD/incompl.fna");
			#print "$inD/incompl.NAl.pre.$idP.fna\n";
			if (-e "$inD/incompl.NAl.pre.$idP.fna"){ #new format
				#print "CCCC\n";
				systemW "rm $inD/incompl.NAl.$idP.fna" if (-e "$inD/incompl.NAl.$idP.fna");
				systemW "cp $inD/incompl.NAl.pre.$idP.fna $inD/incompl.NAl.$idP.fna";
			}
			#die();
			open my $OO,">>","$inD/incompl.NAl.$idP.fna" or die "Can't open $inD/incompl.NAl.$idP.fna\n"; print $OO "\n";
			$hr1 = readSam($samF,$OO); #,$remSeqs)
		#	print OO $remSeqs;
			close $OO;
		} elsif ($k==1){
			#my $fref = readFasta("$inD/3Pcompl.fna");
			if (-e "$inD/P35compl.NAl.pre.$idP.fna"){
				systemW "rm $inD/P35compl.NAl.$idP.fna" if (-e "$inD/P35compl.NAl.$idP.fna");
				systemW "cp $inD/P35compl.NAl.pre.$idP.fna $inD/P35compl.NAl.$idP.fna";
			}
			open my $OO,">>","$inD/P35compl.NAl.$idP.fna" or die "Can't open $inD/P35compl.NAl.$idP.fna\n"; print $OO "\n";
			$hr1 = readSam($samF2,$OO);
		#	print OO $remSeqs;
			close $OO;
		}
	#	die("1\n");
		%Hitin = %{$hr1};
		foreach my $hit (keys %Hitin){
			unless (exists($lnk{$hit})){die "Can't find link $hit\n";}
			my $clCnt = scalar(split(/\n/,$cls{$lnk{$hit}}) );
			foreach my $spl (split(/\n/,$Hitin{$hit})){
				$cls{$lnk{$hit}} .= "\n$clCnt\t".$spl;
				$totCnt++;$clCnt++;
			}
			#die "" if ($totCnt > 10);
		}
	}

		#die("$inD/P35compl.NAl.$idP.fna");

	open O,">$outFcls"; my $totCls=0;
	foreach my $cl (keys %cls){
		$totCls++;
		my $ostr = $cl."\n".$cls{$cl};
		print O $ostr."\n";
	}
	close O;
	#print LOG "final Clusters (incomplete + complete) : $totCls\n";
	print "Results $outFcls\n";
	
	my $Cls2ndFNA = secondaryCls($inD,$idP);
	
	
	my ($inCclN,$inCclNmember) = rewriteClusNumbers($Cls2ndFNA,$totCls);
	print "Concatenating Cluster files\n";
	systemW("cat $Cls2ndFNA.clstr >> $outFcls");
	print "Concatenating Cluster Seed fna files\n";
	systemW("cat $Cls2ndFNA  $completeFNA > $outFfna");
	print LOG "IncomplComplGeneClus	$inCclN\n";
	print LOG "IncomplComplGeneClusMember	".($inCclNmember+$totM)."\n";
	close LOG;
	
	unless (-d "$inD/COG/"){print"No COG specific genes found\n";return;}
	
	#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	#look for COG genes
	print "$inD/COG/\n";
	opendir(DIR, "$inD/COG/") or die $!;
	#COG0087.0.95
	#print readdir(DIR)."\n\n";
	my @cogfiles = sort (grep {/^COG[\d\.]*\.fna$/ } readdir(DIR)); close DIR;#&& -f "$inD/COG/$_" 
	my $logstr = "";
	#die "@cogfiles"."\n";
	if (@cogfiles < 40){die"\n\nless than 40 FMG genes!\n".@cogfiles."\n@cogfiles\n";}
	my $COGcnt =0; my $inCclN2 = 0;
	foreach my $cogFNA (@cogfiles){
		$inCclN+=100; $COGcnt++;
		($inCclN2,$inCclNmember) = rewriteClusNumbers("$inD/COG/".$cogFNA,$inCclN);
		#die "$cogFNA\ncogFNA\n";
		systemW("cat $inD/COG/$cogFNA.clstr >> $outFcls");
		systemW("cat $inD/COG/$cogFNA  >> $outFfna");
		$cogFNA =~ /(COG\d+)\./; my $cog = $1;
		$logstr .= "$cog	$inCclN	$inCclN2\n";
		$inCclN = $inCclN2;
	}
	print "\nFound $COGcnt FMG genes\n";
	#print "$logstr\n";
	open O,">$inD/FMGclusN.log"; print O $logstr; close O;
}

sub writeMG_COGs(){
	my ($GCd) = @_;
	die "cant' work, since ordering not given. used annotateMGwMotus.pl instead";
	my $FMGd = "$GCd/FMG/";
	system "mkdir -p $FMGd";
	open I,"<$GCd/qsubsAlogs/FMGclusN.log";
	while (my $l = <I>){
		chomp $l;
		my @spl = split /\t/,$l;
		my @range = $spl[1] .. $spl[2];
		my $cmd = "$samBin faidx $GCd/compl.incompl.95.fna ". join (" ", @range) . " > $FMGd/$spl[0].gc.fna\n";
		system $cmd;
		$cmd = "$samBin faidx $GCd/compl.incompl.95.prot.faa ". join (" ", @range) . " > $FMGd/$spl[0].gc.faa";
		system $cmd;
	}
	close I;
}

sub secondaryCls(){
	my ($inD,$cdhID) = @_;
	my $cmd="";
	my $outfna = "$inD/incompl.rem.$cdhID.fna";
	if (-e $outfna){return($outfna);}
	#$cmd .= $cdhitBin."-est -i $bdir/P35compl.NAl.$cdhID.fna -o $bdir/P35compl.$cdhID.fna -n 9 -G 0 -M 5000 -aL 0.5 -aS 0.95 $defaultsCDH\n";
	#die("cdf\n");
	#system("cat $inD/P35compl.NAl.$cdhID.fna >> $inD/incompl.NAl.$cdhID.fna\n");
	#size sort
	#my $suc = systemW("cat $inD/P35compl.NAl.$cdhID.fna $inD/incompl.NAl.$cdhID.fna | perl -e 'while (<>) {\$h=\$_; \$s=<>; \$seqs{\$h}=\$s;} foreach \$header (reverse sort {length(\$seqs{\$a}) <=> length(\$seqs{\$b})} keys \%seqs) {print \$header.\$seqs{\$header}}' > $inD/incompl.NAl.srt.$cdhID.fna");
	my $suc = systemW("cat $inD/P35compl.NAl.$cdhID.fna $inD/incompl.NAl.$cdhID.fna  > $inD/incompl.NAl.srt.$cdhID.fna");
	#my $hr = readFasta("$inD/P35compl.NAl.$cdhID.fna");
	#my $hr2 = readFasta("$inD/incompl.NAl.$cdhID.fna");
	#my %remGenes = ( %{$hr}, %{$hr2} ); $hr=0;$hr2=0;
	#my @keys = sort { length($remGenes{$a}) <=> length($remGenes{$b}) } keys(%h);

#	systemW($cdhitBin."-est -i $inD/incompl.NAl.srt.$cdhID.fna -o $outfna -n 9 -G 0 -aL 0.3 -aS 0.8 $defaultsCDH\n") unless (-e $outfna);
	$cmd = clusterFNA( "$inD/incompl.NAl.srt.$cdhID.fna", "$outfna",0.8,0.6,"$cdhID",$numCor,0);
	systemW($cmd);
	#$cmd .= "rm -f $inD/incompl.NAl.$cdhID.fna\n";
	#$cmd .= "rm -f $inD/P35compl.NAl.$cdhID.fna $inD/35compl.$cdhID.align.sam $inD/incompl.$cdhID.align.sam\n";
	return($outfna);
}

sub readCDHITCls(){
	my ($iF) = @_;
	my %retCls; my %retRepSeq; my %clsIDs;
	open I,"<$iF";
	my $clName = "";
	my $clNum=0; my $totMem=0;
	
	while (my $line = <I>){
		chomp $line;
		if ($line =~ m/^>/){#open new cluster
			$clName = $line; $clNum++; $totMem++; next;
		}
		$totMem++;
		if (exists($retCls{$clName})){
			$retCls{$clName} .= "\n".$line;
		} else {
			$retCls{$clName} = $line;
		}
		if ($line =~ m/\*$/){#cluster seed
			#my @tmp = split(/\s*/,$line);
			$line =~ m/>(.*)\.\.\./;
			#print $1."\n";;
			$retRepSeq{$1} = $clName;
		} else {
			$line =~ m/>(.*)\.\.\. at .\/([0-9\.]+)%/;
			if (!exists $clsIDs{$clName} ){
				$clsIDs{$clName} = $2;
			} else {
				$clsIDs{$clName} .= ",".$2;
			}
		}
	}
	return(\%retCls,\%retRepSeq,$clNum, $totMem,\%clsIDs);
}





sub geneCatFunc{
	my ($GCd,$tmpD, $DB, $ncore) = @_;
	my $query = "$GCd/compl.incompl.95.prot.faa";
	my $outD = $GCd."/Anno/Func/";
	#my $DB = "NOG";
	#my $ncore = 40; 
	my $fastaSplits=15;
	
	
	my $curDB = $DB;#"NOG";#CZy,ABRc,KGM,NOG
	
	my %optsDia = (eval=>1e-8,percID=>25,minPercSbjCov=>0.3,fastaSplits=>$fastaSplits,ncore=>$ncore,
			splitPath=>$GLBtmp,keepSplits=>0,redo=>0,minAlignLen=>30, minBitScore=>45);
			
			
	my ($allAss,$jdep) = assignFuncPerGene($query,$outD,$tmpD,$curDB,\%optsDia,$QSBoptHR);
	my $tarAnno = "${allAss}geneAss.gz";
	my $tmpP2 = "$tmpD/CNT_1e-8_25//";
	#create actual COG table
	my $cmd = "";
	$tarAnno =~ s/\.gz$//;
	
	#$cmd	.= "gunzip $tarAnno.gz\n";
	$cmd .= "zcat $tarAnno.gz | sed 's/\\t/;/g' | sed 's/;/\\t/' > $tarAnno\n";
	#$cmd .= "$rareBin sumMat -i $GCd/Matrix.mat -o $outD/${shrtDB}L1.mat -refD $GCd/NOGparse.NOG.GENE2NOG; gzip $GCd/NOGparse.NOG.GENE2NOG.gz\n";
	
	$cmd .= "$rareBin sumMat -i $GCd/Matrix.mat -o $outD/$curDB -refD $tarAnno\n";
	$cmd .= "rm $tarAnno\n" if (length($tarAnno) > 2);
	#gzip $tarAnno\n";
	#copy interesting files to final dir
	#if ($curDB eq "ABRc"){
#		$cmd.= "zcat $tmpP2/ABRcparse.ALL.cnt.CATcnts.gz > $outD/ABR_res.txt\n" ;
#	}
#	if ($curDB eq "CZy"){
#		$cmd.= "zcat $tmpP2/CZyparse.ALL.cnt.CATcnts.gz > $outD/CZySubstrates.txt\n";
#		$cmd.= "zcat $tmpP2/CZyparse.CZy.ALL.cnt.cat.cnts.gz > $outD/CZyEnzymes.txt\n";
#	}
#	if ($curDB eq "TCDB"){
#		$cmd.= "zcat $tmpP2/TCDBparse.ALL.cnt.CATcnts.gz > $outD/TCDB.cats.txt\n";
#	}
#die $cmd."\n";
	unless (-e "$outD/${curDB}L0.txt"){
		if (0 && -e $tarAnno){ #already exists
			systemW $cmd 
		} else {
			($cmd,$jdep) = qsubSystem($qsubDir."${curDB}_matrix.sh",$cmd,1,"5G","${curDB}_mat",$jdep,"",1,[],$QSBoptHR);
		}
	}
	
	if ($curDB eq "KGM"){
		#calc_modules("$outD/${curDB}L0.txt","$outD/modules/",0.5,0.5);#$ModCompl,$EnzCompl);
	}

}

#simply rewrites original fasta names to counts used in my genecats
sub rewriteFastaHdIdx{ # #replaces ">MM2__C122;_23" with number from gene catalog
	my ($inf,$hr) = @_;
	my %gene2num = %{$hr};
	my $numHd =0;
	open I,"<$inf" or die "Can't open fasta file $inf\n"; 
	open O,">$inf.tmp" or die "can't open tmp fasta out $inf.tmp\n";
	while (my $l = <I>){
		if ($numHd > 100){
			print "Seems like $inf heads were already reformated to number sheme!\n";
			 close I; close O; system "rm $inf.tmp"; return;
		}
		if ($l =~ m/^>/){
			chomp $l;
			my $name = substr($l,1);
			if ($name =~ m/^\d+$/ && !exists($gene2num{$name})){
				$numHd++;
				print O ">".$name."\n";
			} else {
				unless(exists($gene2num{$name})){die "can not identify $name gene in index file while rewritign nt fna names $inf\n";}
				print O ">".$gene2num{$name}."\n";
			}
		} else {
			print O $l;
		}
	}
	close I; close O;
	systemW "rm -f $inf; mv $inf.tmp $inf";
}
sub readSam($$){
	my ($iF,$OO) = @_;#$fref,
	#my %fas = %{$fref};
	open I,"<$iF" or die "Can't open $iF\n";
	my $cnt = 0; my $totLines = 0;
	my $add2file=0; my $add2cls=0;
	my %ret; #my $fasStr = "";
	print $OO "\n";
	while (my $line = <I>){
		chomp $line; $totLines++;
		my @sam = split(/\t/,$line);
		my $qu = $sam[0]; my $ref = $sam[2];
		#if ($qu =~ m/MM28__C41733_L=413;_1/){print "TRHERE\n";}
		my $xtrField = join("\t",@sam[11..$#sam]);
		#die $xtrField;
		$xtrField =~ m/XM:i:(\d+)\s.*XO:i:(\d+)\s.*XG:i:(\d+)/;
		my $refL = length($sam[9]);
		#print "$1 $2 $3 $refL ".$1/$refL." ".($2+$3)/$refL."\n";
		#95% id || 90% seq length
		my $pid = $1/($refL-$2-$3);
		if ( ($2+$3)/$refL > 0.1 || $pid > 0.05){ #not good enough hit criteria, attach to fasta
			#print $qu."\n";
			my $nqu = ">".$qu;
			#die "Can't find $qu in ref fasta\n" unless(exists($fas{$nqu}));
			#experimental TODO
			if (length($sam[9]) > 100){ #too short hits don't need to be attached..
				print $OO $nqu."\n".$sam[9]."\n";#$fas{$nqu}."\n";
				$add2file++;
			}
			#die $nqu."\n".$sam[9]."\n";
			next;
		}
		my $mism = $1; my $gaps = $2+$3;
		#$cnt++;
		my $clsStr = $refL-$2-$3."nt, >".$qu."... at +\/". int((1-$pid)*100) .".00%";
		if (exists($ret{$ref})){
			$ret{$ref} .= "\n".$clsStr
		} else {
			$ret{$ref} = $clsStr;
		}
		$add2cls++;
		#if ($qu =~ m/MM28__C41733_L=413;_1/){print "print\n";}

		#print $ret{$ref}."\n";
		#die if ($cnt == 10);
	}
	close I;
	print LOG $add2cls." hits to clusters, $add2file added FNAs to be reclustered (of ".$totLines." lines) in $iF\n";
	return (\%ret);
}

sub FOAMassign{
	my ($GCd,$tmpD, $DB) = @_;
	my $query = "$GCd/compl.incompl.95.prot.faa";
	my $fastaSplits=10;
	my $ar = splitFastas($query,$fastaSplits,$GLBtmp."DB/");
	my @subFls = @{$ar};
	my @jdeps; my @allFiles;
	my $N = 20;my $jdep=""; my $colSel = 4;
	my $tmpSHDD = $QSBoptHR->{tmpSpace};
	$QSBoptHR->{tmpSpace} = "150G"; #set option how much tmp space is required, and reset afterwards

	for (my $i =0 ; $i< @subFls;$i++){
		my $tmpOut = "$tmpD/$DB.hmm.dom.$i";
		my $outF = "$GCd/assig.$DB.$i";
		my $cmd = "mkdir -p $tmpD\n";
		if ($DB eq "FOAM"){
			$cmd .= "$hmmBin3 --cpu $N -E 1e-05 --noali --domtblout $tmpOut $FOAMhmm $subFls[$i] > /dev/null\n";
			
		} elsif ($DB eq "ABR") {
			#--tblout=<output tab-separated file>
			$cmd .= "$hmmBin3 --cpu $N --domtblout $tmpOut --cut_ga $ABresHMM $subFls[$i] > /dev/null\n";
			$colSel = 5;#select gene name
		}
		$cmd .= "sort $tmpOut > $tmpOut.sort\n";
		#DEBUG
		#$cmd .= "cp $tmpOut.sort $GCd\n";
		
		$cmd .= "python $hmmBestHitScr $tmpOut.sort > $tmpOut.sort.BH\n";
		$cmd .= "awk '{printf (\"%s\\t%s\\n\", \$1,\$$colSel)}' $tmpOut.sort.BH |sort > $outF\n";
		$cmd .= "rm -f -r $tmpOut* $subFls[$i]\n";
		my $jobName = "$DB"."_$i";
		#die $cmd."\n";
		my ($cmdRaw,$jdep) = qsubSystem($qsubDir."$DB$i.sh",$cmd,$N,"1G",$jobName,"","",1,[],$QSBoptHR);
		push(@jdeps,$jdep);
		push(@allFiles,$outF);
		#if ($i==5){die;}
	}
	$QSBoptHR->{tmpSpace} = $tmpSHDD; 
	#last job that converges all
	my $assigns = "$GCd/$DB.assign.txt";
	my $cmd= "cat ".join(" ",@allFiles). " > $assigns\n";
	$cmd .= "rm -f ".join(" ",@allFiles) . "\n";
	#tr [:blank:] \\t
	$cmd .= "$rareBin sumMat -i $GCd/Matrix.mat -o $GCd/$DB.mat -refD $assigns\n";
	print "@jdeps\n";
	($cmd,$jdep) = qsubSystem($qsubDir."collect$DB.sh",$cmd,1,"40G","$DB"."Col",join(";",@jdeps),"",1,[],$QSBoptHR);
	#return $jdep,$outF;
}



# minlengthpercent=0    (mlp) Smaller contig must be at least this percent of larger contig's len    gth to be absorbed.
# minoverlappercent=0   (mop) Overlap must be at least this percent of smaller contig's length to     cluster and merge.
# minoverlap=200        (mo) Overlap must be at least this long to cluster and merge.


# /g/bork3/home/hildebra/bin/bbmap/./dedupe.sh in=/g/scb/bork/hildebra/SNP/GCs/SimuB/B0/compl.fna out=/g/scb/bork/hildebra/SNP/GCs/SimuB/X0/ddtest.compl.fna exact=f threads=20 outd=/g/scb/bork/hildebra/SNP/GCs/SimuB/X0/drop.fna minidentity=95 storename=t renameclusters=t usejni=t cluster=t k=18 -Xmx50g


















