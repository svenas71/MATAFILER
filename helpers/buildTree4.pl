#!/usr/bin/env perl
#perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/helpers/buildTree4.pl -fna /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2//renameTEC2//allFNAs.fna -aa /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2//renameTEC2//allFAAs.faa -cats /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2//renameTEC2//categories4ete.txt -outD /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2/testMSA/ -cores 12 -useEte 0 -NTfilt 0.8 -runIQtree 0 -calcDistMat 1 -continue 0
#perl /g/bork3/home/hildebra/dev/Perl/reAssemble2Spec/helpers/buildTree4.pl -fna /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2//renameTEC2//allFNAs.fna -aa /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2//renameTEC2//allFAAs.faa -cats /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2//renameTEC2//categories4ete.txt -outD /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5//T2/tesssst/ -cores 12 -useEte 0 -NTfilt 0.8 -NonSynTree 0 -SynTree 0 -runRAxML 0 -runGubbins 0
#ARGS: ./buildTree.pl -fna [FNA] -faa [FAA] -cat [categoryFile] -outD [outDir] -cores [CPUs] -useEte [1=ETE,0=this script] -NTfilt [filter]
#versions: ver 2 makes a link to nexus file formats, to be used in MrBayes and BEAST etc
#8.12.17: added mod3 from Mechthild

# perl /g/scb/bork/luetge/pangenomics/speciation/dNdS/scripts/buildTree4_mod2.pl -fna /g/scb/bork/luetge/pangenomics/speciation/dNdS/fasta/allOrtho_freeze11_cluster_10.fna -aa /g/scb/bork/luetge/pangenomics/speciation/dNdS/fasta/allOrtho_freeze11_cluster_10.faa -cats /g/scb/bork/luetge/pangenomics/speciation/dNdS/catFiles/freeze11_cluster_10_categories4MSA.txt -outD /g/scb/bork/luetge/pangenomics/speciation/dNdS/outFiles/test/ -cores 12 -useEte 0 -NTfilt 0.8 -NonSynTree 0 -SynTree 0 -runRAxML 0 -runGubbins 0 -runLengthCheck 0 -runDNDS 0 -genesToPhylip 0 -continue 1 -runFastgear 0 -runFastGearPostProcessing 1 -clustername cluster_10

use warnings;
use strict;
use threads ('yield',
                 'stack_size' => 64*4096,
                 'exit' => 'threads_only',
                 'stringify');
use Mods::IO_Tamoc_progs qw(getProgPaths);
use Mods::GenoMetaAss qw( systemW readFasta writeFasta convertMSA2NXS);
use Mods::phyloTools qw(runRaxML runQItree runFasttree fixHDs4Phylo);
use Getopt::Long qw( GetOptions );
use Bio::Phylo::IO;


sub convertMultAli2NT;
sub mergeMSAs;
sub synPosOnly;
sub calcDisPos;#gets only the dissimilar positions of an MSA, as well as %id similarity
sub calcDisPos2;#de novo aligns pairwise via vsearch and calcs id (iddef 2)
sub calcDiffDNA;
sub runCodeml;
sub runFastgear;
sub mergePids;

my $doPhym= 0;

my $pal2nal = getProgPaths("pal2nal"); #"perl /g/bork3/home/hildebra/bin/pal2nal.v14/pal2nal.pl";
#die $pal2nal;
my $clustaloBin = getProgPaths("clustalo");#= "/g/bork3/home/hildebra/bin/clustalo/clustalo-1.2.0-Ubuntu-x86_64";
my $fasta2phylip = getProgPaths("fasta2phylip_scr");
my $phymlBin = getProgPaths("phyml");
my $msapBin = getProgPaths("msaprobs");
my $trimalBin = getProgPaths("trimal");
my $pigzBin  = getProgPaths("pigz");
my $trDist = getProgPaths("treeDistScr");
my $eteBin = "";
my $gubbinsBin = "/g/bork3/home/hildebra/bin/gubbins/python/scripts/run_gubbins.py";
my $pamlBin = "/g/bork3/home/luetge/softs/paml4.9e/bin/codeml";

my $fastgearBin = "/g/bork3/home/luetge/softs/fastGEARpackageLinux64bit/run_fastGEAR.sh";
my $matlabBin = "/g/bork3/home/luetge/softs/matlab/v901";
my $fastgearSummaryBin = "/g/bork3/home/luetge/softs/fastGearPostprocessingLinux64bit/run_collectRecombinationStatistics.sh";
my $fastgearReconstrBin = "/g/bork3/home/luetge/softs/fastGearPostprocessingLinux64bit/run_startAncestryReconstruction.sh";
my $fastgearReorderBin = "/g/bork3/home/luetge/softs/fastGearPostprocessingLinux64bit/run_reorderMultipleGenes.sh";

#die "TODO $trimalBin\n";
#trimal -in /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5/T2/tesssst/MSA/COG0185.faa -out /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5/T2/tesssst/MSA/tst.fna -backtrans /g/scb/bork/hildebra/SNP/GNMass3/TECtime/v5/T2/tesssst/inMSA0.fna -keepheader -keepseqs -noallgaps -automated1 -ignorestopcodon
#some runtim options...
#my $ncore = 20;#RAXML cores
my $ntFrac =2; 
my $clustalUse = 1; #do MSA with clustal (1) or msaprobs (0) 
if ($clustalUse == 0){print "Warning:  MSAprobs with trimal gives warnings (ignore them)\n";}
my $calcDistMat = 0; #distmat of either AA or NT (depending on MSA)
my $calcDistMatExt = 0; #distmat of other AA or NT (depending on MSA), e.g. running two times an MSA
my $calcDistMatExtGo = 0;

my $ntCnt =0; my $bootStrap=0;
my ($fnFna, $aaFna,$cogCats,$outD,$ncore,$Ete, $filt,$smplDef,$smplSep,$calcSyn,$calcNonSyn,
			$useAA4tree,$calcDNAdiff) = ("","","","",12,0,0.8,1,"_",1,0,0,0);
my ($continue,$isAligned) = (0,0);#overwrite already existing files?
my $outgroup="";
my $fixHeaders = 0;
my ($doGubbins,$doCFML,$doRAXML,$doFastTree, $doIQTree) = (0,0,0,1, 0);#fastree as default tree builder

#check length of fasta to avoid frameshift
my $doLengthCheck=1;
my $doDNDS=0;
my $doGenesToPh=0;
my $doFastGear=0;
my $doFastGearSummary=0;
my $clusterName="";
my $MSAreq = 1;
my $iqFast=0;


## parameters for codeml
my $selGene=0; 		#run dnds just on subset (given by genesForDNDS) of genes 
my @genesExtra;	#list with selected genes just for dnds
my $locTmpD= "";
my @model= (0,1,2);  # codeml models: 0 -> neutral selection,  (1,2,7,8) -> test for postive selection
my @omegas = (0.3, 1.3); #try different omega values to check for convergence	
my $repeatCounts=2;	#set how often each model should be repeated to check for convergence 
my $MsaD=""; #directory to MSAs for codeml # MSA files need to be named ($gene*.fna) 
my $codemlOutD=""; 
my $treeFile="";


die "no input args!\n" if (@ARGV == 0 );


GetOptions(
	"fna=s" => \$fnFna,
	"aa=s"      => \$aaFna,
	"cats=s"      => \$cogCats,
	"outD=s"      => \$outD,
	"cores=i" => \$ncore,
	"fixHeaders=i" => \$fixHeaders, ## fix the fasta headers, if too long or containing not allowed symbols (nwk reserved)
	"useEte=i"      => \$Ete,
	"NTfilt=f"      => \$filt,
	"smplDef=i"	=> \$smplDef, #is the genome somehow quantified with a delimiter (_) ?
	"smplSep=s" => \$smplSep, #set the delimiter
	"outgroup=s"	=> \$outgroup,
	"NonSynTree=i"	=> \$calcNonSyn,
	"AAtree=i" => \$useAA4tree,
	"calcDistMat=i" => \$calcDistMat,
	"calcDistMatExt=i" => \$calcDistMatExt,
	"calcDiffDNA=i" => \$calcDNAdiff,
	"SynTree=i"	=> \$calcSyn,
	"continue=i" => \$continue,
	"fast=i" => \$iqFast,
	"bootstrap=i" => \$bootStrap,
	"isAligned=i" => \$isAligned,
	"runRAxML=i" => \$doRAXML,
	"runFastTree=i" => \$doFastTree,
	"runIQtree=i" => \$doIQTree,
	"runClonalFrameML=i" => \$doCFML,
	"runGubbins=i" => \$doGubbins,
	"runLengthCheck=i" => \$doLengthCheck,		#check that sequence length can be divided by 3

	"runDNDS=i" => \$doDNDS,			#run dNdS analysis
	"genesForDNDS=s{,}" => \@genesExtra,		#list with selected genes just for dnds
	"DNDSonSubset=i" => \$selGene,			#run dnds just on subset (given by genesForDNDS) of genes
	"DNDS_TmpD=s" => \$locTmpD,
	"codemlRepeats=i" => \$repeatCounts,
	"treefileCodeml=s" => \$treeFile,
	"MSAdirCodeml=s" => \$MsaD,			#directory to MSAs for codeml # MSA files need to be named ($gene*.fna) 
	"outDCodeml=s"=> \$codemlOutD,

	"genesToPhylip=i" => \$doGenesToPh,	
	"runFastgear=i" => \$doFastGear,
	"runFastGearPostProcessing=i" => \$doFastGearSummary,
	"clustername=s" => \$clusterName,
) or die("Error in command line arguments\n");


##### files for codeml
$codemlOutD = "$outD/codeml" if ($codemlOutD eq "");;	
system "mkdir -p  $codemlOutD" unless(-d "$codemlOutD");

if ($doDNDS == 1 && $treeFile eq ""){	die "treefile required for codeml. Set treefileCodeml\n";}
if ($doDNDS == 1 && $MsaD eq ""){	die "Directory to MSAs required for codeml. Set MSAdirCodeml\n";}
if ($doDNDS == 1 && $locTmpD eq ""){	die "TmpD required for codeml. Set DNDS_TmpD\n";}
######


if ($doCFML && !$doRAXML){die "Need RaxML alignment, if Clonal fram is to be run..\n";}

if ($aaFna eq "" || $useAA4tree){	$calcSyn=0;$calcNonSyn=0;}
if ($filt <1){$ntFrac=$filt; print "Using filter with $ntFrac fraction of nts\n";}
if ($outgroup ne ""){print "Using outgroup $outgroup\n";}
if ($bootStrap>0){print "Using bootstrapping in tree building\n";}
if (($calcDistMat || $calcDistMatExt) && $isAligned || !$clustalUse){die"Can't calc distance mat, unless clustalO is being used for MSA\n";}
else {$ntCnt = $filt;}

$MSAreq = 0 if (!$doFastTree && !$doRAXML && !$doCFML && !$doGubbins && !$doIQTree);

my $tmpD = $outD;
system "mkdir -p $tmpD" unless (-d $tmpD);
my $cmd =""; my %usedGeneNms;


my $outD_clust = "";
if($clusterName eq ""){$outD_clust = "$outD/MSA_FG";}
else {my $outD_clust = "/g/bork5/luetge/$clusterName";}

#------------------------------------------
#sorting by COG, MSA & syn position extraction
if ($Ete){
	$cmd = "ete3 build -n $fnFna -a $aaFna -w clustalo_default-none-none-none  -m sptree_raxml_all --cpu $ncore -o $outD/tree --clearall --nt-switch 0.0 --noimg  --tools-dir /g/bork3/home/hildebra/bin/ete/ext_apps-latest"; #--no-seq-checks
	$cmd .= " --cogs $cogCats" unless ($cogCats eq "");
	print "Running tree analysis ..";
	print $cmd."\n";
	die;
	system $cmd . "> $outD/tree/ETE.log";
	print " Done.\n$outD/tree\n";
	exit(0);
}


#general routine, starting with MSA
#followed by merge of MSA / NT -> AA conversion, MSA filter etc
#followed by tree building

if ($fixHeaders){
	if ($cogCats ne ""){die"implement fix hds for cats\naborting\n";}
	$aaFna=fixHDs4Phylo($aaFna);$fnFna = fixHDs4Phylo($fnFna); 
}

my $treeD = "$outD/phylo/";#raxml, fasttree, phyml tree output dir
#my $treeDFT = "$outD/FTtree/";#fasttree output

system "rm -fr $treeD $outD/MSA/" if (!$continue);
system "mkdir -p  $outD/MSA/" unless(-d "$outD/MSA/");
system "mkdir -p  $treeD/" unless(-d "$treeD");
my $multAli = "$outD/MSA/MSAli.fna";
my $multAliSyn = $multAli.".syn.fna";
my $multAliNonSyn = $multAli.".nonsyn.fna";

my $MSAcat = "$outD/MSA/MSAcat.fna";


#DEBUG
#mergePids("$outD/MSA/",40, "NT") ;die;
#my $tmp = "/g/bork5/hildebra/results/TEC2/v5/T2dphylo/rDNA2/fullGenomes/ini16S.fna";
#calcDisPos2($tmp,"$outD/MSA/percID_syn.txt",1); die;

my $phylipD = "$outD/phylip/";
system "mkdir -p  $phylipD" unless(-d $phylipD || !$doGenesToPh);

my @MSAs; my @MSA_AA; my @MSAsSyn; my @MSAsNonSyn;#full MSAs and MSAs with syn / nonsyn pos only
my @MSrm; 
my %FAA ; my %FNA ; my @geneList; my @geneListF;
my $doMSA = 1;
$doMSA =0 if ($continue && -e $multAli && (-e $multAliSyn ||!$calcSyn)&& (-e $multAliNonSyn ||!$calcNonSyn));  ## checks if MSA already exists
#die "$doMSA $continue\n";
#die "$doDNDS\n";
#my @xx = keys %FAA; die "$xx[0] $xx[1]\n$FAA{HM29_COG0185}\n";

if ($doMSA && $cogCats ne ""){
	my $hr = readFasta($aaFna,1); my %FAA = %{$hr};
	#die "$aaFna\n";
	#die $FAA{"1214150.PRJNA171417_05DKX"}."\n";
	$hr = readFasta($fnFna,1); my %FNA = %{$hr};
	#die $FNA{"1214150.PRJNA171417_05DKX"}."\n";		
	print "ReadFasta\n";

	############# test length of fna sequences can be divided by 3 ##############################
		
	if($doLengthCheck){
		my $FNAseq; my $length; my $div;
		while (($FNAseq) = each (%FNA)){
			# do whatever you want with $key and $value here ...
			$length = length($FNA{$FNAseq});
			$div = $length/3;
			#$div = 12.7;
			print "AA seq can not divided by 3 in $FNAseq\n" if($div =~ /\D/);
			#die "$div\n";
		}


	}

	#############################################################################################

	my $cnt = 0; 
	my %samples; my $ogrpCnt=0;#my %genCats; 
	open my $xI,"<$cogCats" or die "Can't open cogcats $cogCats\n";
	while (<$xI>){
		chomp; my @spl = split /\t/;
		@spl = grep !/^NA$/, @spl;#remove NAs
		if (@spl ==0){print "No categories in cat file line $cnt\n";next;}
		$spl[0] =~ m/^(.*)$smplSep(.*)$/;					
		my @spl2 = ($1,$2);#split /$smplSep/,$spl[0] ;	
		#die "@spl\n";		
		my $ogrGenes = "";
		if ($outgroup ne ""){
			foreach my $seq (@spl){
				#my @spl3 = split /$smplSep/,$seq ; 
				$seq =~ m/^(.*)$smplSep(.*)$/;#my @spl3 =($1,$2);
				if ($1 eq $outgroup){$ogrGenes = $seq; $ogrpCnt ++ ; last;}
			}
		}
		
		#die "$spl2[0]\t$spl2[1]\n";
		

		die "Double gene name in tree build pre-concat: $spl2[1]\n" if (exists($usedGeneNms{$spl2[1]}));
		$usedGeneNms{$spl2[1]} = 1;
		#die "@spl\n";
		my $tmpInMSA = "$tmpD/inMSA$cnt.faa";
		my $tmpInMSAnt = "$tmpD/inMSA$cnt.fna";
		my $tmpOutMSA2 = "$outD/MSA/$spl2[1].$cnt.faa";
		my $tmpOutMSA = "$outD/MSA/$spl2[1].$cnt.fna";
		my $tmpOutMSAsyn = "$tmpD/MSA/$spl2[1].$cnt.syn.fna";
		my $tmpOutMSAnonsyn = "$tmpD/MSA/$spl2[1].$cnt.nonsyn.fna";
		open O,">$tmpInMSA" or die "Can;t open tmp faa file for MSA: $tmpInMSA\n";
		open O2,">$tmpInMSAnt" or die "Can;t open tmp fna file for MSA: $tmpInMSAnt\n";
		my $seqType = "AA";my $seqTypeOth = "NT";
		my $seqLength = 0;
		foreach my $seq (@spl){### $seq = genomeX_NOGY
			#print "$seq\n";
			#my @spl2 = split /$smplSep/,$seq; 
			my $seq2 = $seq;
			if (!$smplDef){#create artificial head tag
				#TODO.. don't need it now for tec2, since no good NCBI taxid currently...
			}
			$seq2 =~ m/^(.*)$smplSep(.*)$/;#my @spl2 =($1,$2);
			#die "$seq3\n";
			#die "$FAA{$seq}\n";
			$samples{$1} = 1; #$genCats{$spl2[1]} = 1; 
			die "can't find AA seq $seq\n" unless (exists ($FAA{$seq}));
			die "can't find fna seq $seq\n" if (!exists ($FNA{$seq}) && !$useAA4tree);
			$FAA{$seq} =~ s/\*//g if (!$clustalUse);
			print O ">$seq2\n$FAA{$seq}\n";
			if (!$useAA4tree){
				print O2 ">$seq2\n$FNA{$seq}\n";
			}
			$seqLength += length($FNA{$seq});
		}
		$seqLength /= @spl;
		#die "@genomeList\n";
		close O;close O2;
		#dist mat related
		my $tmpDMatOth = "$outD/MSA/${seqTypeOth}_clustalo_percID_${cnt}_".int($seqLength).".txt";
		my $tmpDMat = "$outD/MSA/${seqType}_clustalo_percID_${cnt}_".int($seqLength).".txt";
		my $inFastaOth = $tmpInMSAnt;
		
		if ($clustalUse){
			if (1 || !$calcDistMat){
				$cmd = $clustaloBin." -i $tmpInMSA -o $tmpOutMSA2 --outfmt=fasta --threads=$ncore --force\n";
			} elsif (0) {
			#do not use this path any longer, but vsearc implementation
			#--use-kimura
				$cmd = $clustaloBin." -i $tmpInMSA -o $tmpOutMSA2 --outfmt=fasta --percent-id --distmat-out $tmpDMat --threads=$ncore --force --full\n";
				
				if ($calcDistMatExt && -e $inFastaOth){
					$cmd .= $clustaloBin." -i $inFastaOth -o $tmpOutMSA2.tmp --outfmt=fasta --percent-id --distmat-out $tmpDMatOth --threads=$ncore --force --full\n";
					$cmd .= "rm $tmpOutMSA2.tmp\n";
					$calcDistMatExtGo=1
				}
			}

		} else {
			$cmd = "$msapBin -num_threads $ncore $tmpInMSA > $tmpOutMSA2";
		}
		#die $cmd;
		systemW $cmd unless (-s $tmpOutMSA2 && $continue);
		
		if ($calcDistMat){ #for dmat: calc each gene spearately and merge scores later
			my $status  = calcDisPos2($tmpInMSA,$tmpDMat,0);
#			if ($calcDistMatExt && -e $inFastaOth){
			if (-e $inFastaOth){ #no flow control..
				$status = calcDisPos2($inFastaOth,$tmpDMatOth,1);
				$calcDistMatExtGo = $status;
			} else { $calcDistMatExtGo = 0;}

		}
		#die "@MSAs\n";
		if (!$useAA4tree){
			#this part now is all concerned about NT level things..
			convertMultAli2NT($tmpOutMSA2,$tmpInMSAnt,$tmpOutMSA);
			#die("XX\n") if ($spl2[1] eq "COG0081");
			($tmpOutMSAsyn,$tmpOutMSAnonsyn) = synPosOnly($tmpOutMSA,$tmpOutMSA2,$tmpOutMSAsyn,$tmpOutMSAnonsyn,0,$ogrGenes,$calcSyn,$calcNonSyn);
			push (@MSAs,$tmpOutMSA);
			push (@MSAsSyn,$tmpOutMSAsyn) if ($tmpOutMSAsyn ne "");
			push (@MSAsNonSyn,$tmpOutMSAnonsyn) if ($tmpOutMSAnonsyn ne "");
			#die "@MSAs\n";
		} else {
			push (@MSA_AA,$tmpOutMSA2);
		}
		system "rm -f $tmpInMSA $tmpInMSAnt";# $tmpOutMSA2";
		push (@MSrm,$tmpOutMSA2,$tmpOutMSA);
		#die "$MSrm[1]\n";
		
		if ($doDNDS || $doGenesToPh){
			#die "$tmpOutMSA\n";
			my $MSAfn = $tmpOutMSA;
			#die "$MSAfn\n";

			#1.convert MSA to phylip
			my $cmd2 = "rm -f $phylipD/$spl2[1].$cnt.fna.ph*; $fasta2phylip -c 50 $MSAfn > $phylipD/$spl2[1].$cnt.fna.ph\n";
			#die "$cmd2\n";
			if (system $cmd2) {die "fasta2phylim failed:\n$cmd2\n";} 
			#2. create hash with genomes for tree pruning
			push(@geneList, $spl2[1]);				
		}
		#die;

		$cnt ++;
		print "$cnt "; 

	}
	close $xI;
	
	my $mergPIDtag = "_merge";
	mergePids("$outD/MSA/",$cnt, "AA",$mergPIDtag) if ($calcDistMat); #merge different percIDs
	mergePids("$outD/MSA/",$cnt, "NT",$mergPIDtag) if ($calcDistMat); #merge different percIDs
	
	#$seqCount = $cnt;		
	#die "$seqCount\n";

	if ($outgroup ne ""){print "Found $ogrpCnt of $cnt outgroup sequences\n";}
	#die;
	#die "@MSAs\n";
	#merge cogcats - can go to tree from here
	if ($useAA4tree){
		mergeMSAs(\@MSA_AA,\%samples,$multAli,0); #sames files as in @MSrm
	} else {
		mergeMSAs(\@MSAs,\%samples,$multAli,0);
		mergeMSAs(\@MSAsSyn,\%samples,$multAliSyn,1) if ($calcSyn);
		mergeMSAs(\@MSAsNonSyn,\%samples,$multAliNonSyn,1) if ($calcNonSyn);
	}
	
	#die();
	#system "rm -f ".join(" ",@MSrm)." ".join(" ",@MSAsSyn); 
} elsif ($doMSA) {#no marker way, single gene
	print "No gene categories given, assumming 1 gene / species in input\n";
	my $tmpInMSA = $aaFna;
	#my $tmpInMSAnt = $fnFna;
	my $tmpOutMSA2 = "$tmpD/outMSA.faa";
	my $tmpOutMSAsyn = $multAliSyn;#"$tmpD/outMSA.syn.fna";
	my $tmpOutMSAnonsyn = $multAliNonSyn;
	#print "$tmpInMSAnt\n";
	my $numFas;
	if (-e $aaFna){ #just faster to use aa file..
		$numFas = `grep -c '^>' $aaFna`;
	} else {
		$numFas = `grep -c '^>' $fnFna`;
	}
	chomp $numFas;
	#die "$fnFna $numFas\n"; 
	my $seqType = "AA";
	my $seqTypeOth = "NT";
	my $inFasta = $aaFna;
	my $inFastaOth = $fnFna;
	my $mainTypeIsAA=1;
	if ($aaFna eq ""){ #always choose AA as default alignment, nt is only fallback
		$inFasta = $fnFna ;
		$inFastaOth = $aaFna;
		$seqType = "NT";
		$seqTypeOth = "AA";
		$mainTypeIsAA = 0;
	}
	if ($numFas <= 1){print "Not enough Sequences\n"; exit(0);}
	if ($isAligned){
		#if ($aaFna ne ""){die "AA input can not be defined, if input is specified as being aligned!\n";}
		#just cp infile to MSA location
		system "cp $inFasta $tmpOutMSA2";
	} elsif ($clustalUse){
		if (1 || !$calcDistMat){
			$cmd = $clustaloBin." -i $inFasta -o $tmpOutMSA2 --outfmt=fasta --threads=$ncore --force\n";
		} elsif (0) {
		#--use-kimura
			$cmd = $clustaloBin." -i $inFasta -o $tmpOutMSA2 --outfmt=fasta --percent-id  --distmat-out $outD/MSA/${seqType}_clustalo_percID_0_1.txt --threads=$ncore --force --full\n";
			if (!$calcDistMatExt && -e $inFastaOth){
				$cmd .= $clustaloBin." -i $inFastaOth -o $tmpOutMSA2.tmp --outfmt=fasta --percent-id  --distmat-out $outD/MSA/${seqTypeOth}_clustalo_percID_0_1.txt --threads=$ncore --force --full\n";
				$cmd.="rm $tmpOutMSA2.tmp\n";
			}
		}

	} else {
		#$cmd = "sed -i 's/\\*//g' $inFasta\n";
		$cmd .= "$msapBin -num_threads $ncore $inFasta > $tmpOutMSA2\n";
	}
	if ($calcDistMat){
		if (-e $tmpInMSA){
			calcDisPos2($tmpInMSA,"$outD/MSA/${seqType}_vsearch_percID.txt",!$mainTypeIsAA);
		}
		if (-e $inFastaOth){
			calcDisPos2($inFastaOth,"$outD/MSA/${seqTypeOth}_vsearch_percID.txt",$mainTypeIsAA);
		}
	}

	unless ($continue && -e  $tmpOutMSA2){
		systemW $cmd ; print "finished MSA\n";
		#mergePids("$outD/MSA/",1, $seqType) if ($calcDistMat); #merge different percIDs
		#mergePids("$outD/MSA/",1, $seqTypeOth) if ($calcDistMatExt); #merge different percIDs
	}

	if ($tmpInMSA ne "" && !$useAA4tree){
		convertMultAli2NT($tmpOutMSA2,$fnFna,$multAli);
		synPosOnly($multAli,$tmpOutMSA2,$tmpOutMSAsyn,$tmpOutMSAnonsyn,0,"",$calcSyn,$calcNonSyn);
		#system "rm $tmpInMSA $fnFna $tmpOutMSA2";
		system "rm $tmpOutMSA2";
		push (@MSAs,$multAli);
	} elsif (!$useAA4tree) {
		$calcSyn=0;$calcNonSyn=0;
		my $hr = readFasta($tmpOutMSA2,1); writeFasta($hr,$multAli);#complicated way to shorted headers of infile
		#system "mv $tmpOutMSA2 $multAli";
		push (@MSAs,$multAli);
	} else {#useAA4tree
		push (@MSA_AA,$tmpOutMSA2);
		$multAli = $tmpOutMSA2;
		
		#TODO: replace selenocysteine (U) with C, to get raxml to work on these as well
	}
	#$multAli = $tmpOutMSA; $multAliSyn = $tmpOutMSAsyn;
}
#die;

#-------------------------------------------
#Tree prep phase (MSA clean up, conversion, 4fold sites etc)
#convert fasta again

my @thrs;

if ($doRAXML){ #convert MSA to phyllip (RAXML requires this..)
	my $tcmd = "rm -f $multAli.ph*; $fasta2phylip -c 50 $multAli > $multAli.ph\n";
	if (!$useAA4tree){
		$tcmd .= "rm -f $multAliSyn.ph*; $fasta2phylip -c 50 $multAliSyn >$multAliSyn.ph\n" if ($calcSyn);
		$tcmd .= "rm -f $multAliNonSyn.ph*; $fasta2phylip -c 50 $multAliNonSyn >$multAliNonSyn.ph\n"if ($calcNonSyn);
	}
	#die "$tcmd\n";	##--> rm -f /g/scb/bork/luetge/pangenomics/speciation/dNdS/outFiles/test//MSA/MSAli.fna.ph*; perl /g/bork3/home/hildebra/dev/Perl/formating/fasta2phylip.pl -c 50 /g/scb/bork/luetge/pangenomics/speciation/dNdS/outFiles/test//MSA/MSAli.fna > /g/scb/bork/luetge/pangenomics/speciation/dNdS/outFiles/test//MSA/MSAli.fna.ph
	if (system $tcmd) {die "fasta2phylim failed:\n$tcmd\n";}
}
#convert MSA to NEXUS
#convertMSA2NXS($multAli,"$multAli.nxs");

if ($calcDNAdiff){
	calcDiffDNA($multAli,"$outD/MSA/percID_2.txt");
}


my $phyloTree = "";
if ($doGubbins){
	my $outDG = "$outD/gubbins/"; 
	system "mkdir -p $outDG" unless (-d $outDG);
	$outDG .= "GD";
	if ($continue && -e $outDG.".final_tree.tre"&& -e $outDG.".summary_of_snp_distribution.vcf"){
		print "Gubbins result already exists in output folder, run will be skipped\n";
	} else {
		system "rm -rf $outDG\n";
		my $cmdG = "source activate py3k\n";
		$cmdG .= "$gubbinsBin --filter_percentage 50  --tree_builder hybrid --prefix $outDG --threads $ncore $multAli";
		if (0){$cmdG.=" --outgroup $outgroup";}
		$cmdG.="\n";
		$cmdG .= "source deactivate py3k\n";
		systemW $cmdG;
		#die $cmdG."\n";
		print "Gubbins run finished\n";
	}
}

#distamce matrix, this is fast
#system "$trimalBin -in $multAli -gt 0.1 -cons 100 -out /dev/null -sident 2> /dev/null > $outD/MSA/percID.txt\n";
if (0 && !$useAA4tree){ #this is outdated
	calcDisPos($multAli,"$outD/MSA/percID.txt",1) unless(-e "$outD/MSA/percID.txt" && $continue);
	if ($calcSyn){
	#		system "$trimalBin -in $multAliSyn -gt 0.1 -cons 100 -out /dev/null -sident 2> /dev/null > $outD/MSA/percID_syn.txt\n";
		calcDisPos($multAliSyn,"$outD/MSA/percID_syn.txt",1);
	}
	if ($calcNonSyn){
		#system "$trimalBin -in $multAliNonSyn -gt 0.1 -cons 100 -out /dev/null -sident 2> /dev/null > $outD/MSA/percID_nonsyn.txt\n";
		calcDisPos($multAliNonSyn,"$outD/MSA/percID_nonsyn.txt",1);
	}
} elsif (0) {
	calcDisPos($multAli,"$outD/MSA/AA_percID.txt",1) unless(-e "$outD/MSA/percID.txt" && $continue);
}

#-------------------------------------------
#Tree building part with RaxML, IQtree, fasttree2, phyml

if ($doFastTree){
	#system "mkdir -p $treeDFT" unless (-d $treeDFT);
	my $fasttree = "$treeD/FASTTREE_allsites.nwk";
	unless ($continue && -e $fasttree){
		runFasttree($multAli,$fasttree,$useAA4tree,$ncore);
	}
}
if ($doIQTree){
	my $IQtree = "$treeD/IQtree.nwk";
	unless ($continue && -e "$IQtree.treefile"){
		my$iqAutoModel=1;
		runQItree($multAli,$IQtree,$ncore,$outgroup,$bootStrap,$useAA4tree,$iqFast,$iqAutoModel);
	}
	$IQtree = "$treeD/IQtree_allsites";
	unless ($continue && -e "$IQtree.treefile"){ #and slow..
		#runQItree($multAli,$IQtree,$ncore,$outgroup,$bootStrap,$useAA4tree,0);
	}
}

if ($doRAXML){
	my $BStag = ""; if ($bootStrap>0){$BStag="_BS$bootStrap";}
	runRaxML("$multAli.ph",$bootStrap,$outgroup,"$treeD/RXML_allsites$BStag.nwk",$ncore,$continue,!$useAA4tree);
	$phyloTree = "$treeD/RXML_allsites$BStag.nwk";
	if ($calcSyn){
		runRaxML("$multAliSyn.ph",$bootStrap,$outgroup,"$treeD/RXML_syn$BStag.nwk",$ncore,$continue,1) ;
	}
	if ($calcNonSyn){
		runRaxML("$multAliNonSyn.ph",$bootStrap,$outgroup,"$treeD/RXML_nonsyn$BStag.nwk",$ncore,$continue,1);
	}
}
if ($doCFML){
	my $outDG = "$outD/clonalFrameML/";
	system "mkdir -p $outDG" unless (-d $outDG);
	$outDG .= "CFML";
	my $CFMLbin = "/g/bork3/home/hildebra/bin/ClonalFrameML/src/./ClonalFrameML";
	my $cmd = "$CFMLbin $phyloTree $multAli $outDG\n";
	die $cmd;
}

#phyml

if ($doPhym){
	my $tcmd = "";
	my $nwkFile = "$treeD/tree_phyml_all.nwk";
	my $nwkFile2 = "$treeD/tree_phyml_syn.nwk";
	$tcmd = "$phymlBin --quiet -m GTR --no_memory_check -d nt -f m -v e -o tlr --nclasses 4 -b 2 -a e -i $multAli.ph > $nwkFile\n";
	push(@thrs, threads->create(sub{system $tcmd;}));
	$tcmd = "$phymlBin --quiet -m GTR --no_memory_check -d nt -f m -v e -o tlr --nclasses 4 -b 2 -a e -i $multAliSyn.ph > $nwkFile2\n";
	push(@thrs, threads->create(sub{system $tcmd;}));
}
for (my $t=0;$t<@thrs;$t++){
	my $state = $thrs[$t]->join();
	if ($state){die "Thread $t exited with state $state\nSomething went wrong with RaxML\n";}
}
#system "rm -f $multAli.ph $multAliSyn.ph $multAliNonSyn.ph";

#die "$distTree_scr -d -a --dist-output $raxD/distance.syn.txt $raxD/RXML_sym.nwk\n";



#### compute dNdS values ######

if($doDNDS){
	if($cogCats ne ""){
		open I,"<$cogCats" or die "Can't open cogcats $cogCats\n"; 
		while (<I>){
			my $cnt2 =0;
			chomp; my @spl = split /\t/;
			@spl = grep !/^NA$/, @spl;#remove NAs
			if (@spl ==0){print "No categories in cat file line $cnt2\n";next;}
			$spl[0] =~ m/^(.*)$smplSep(.*)$/;					
			my @spl2 = ($1,$2);#split /$smplSep/,$spl[0] ;	
			#die "@spl\n";
			push(@geneList, $spl2[1]);
			$cnt2 ++;
		}
	}

	my $dndsDir = "$outD/codeml";
	system "mkdir -p  $dndsDir" unless(-d "$dndsDir");
	my $codemlOutD = "$dndsDir/codemlOutput";
	system "mkdir -p  $codemlOutD" unless(-d "$codemlOutD");
	my $MsaD = "$outD/MSA";

	my $BStag = ""; if ($bootStrap>0){$BStag="_BS$bootStrap";}
	my $treeFile = "$treeD/RXML_allsites$BStag.nwk";

	my $Model= "0 1 2 7 8";  # $Model = 0 -> neutral selection, $Model= "0\s1\s2\s7\s8" -> test for postive selection
	
	runCodeml(\@geneList, $dndsDir, $treeFile, $treeD, $phylipD, $codemlOutD, $MsaD, $Model);   # MSA files and Phylip files need to be named ($gene.$cnt.fna) and ($gene.$cnt.fna.ph)
	
	#if($selGene){		@geneList=@genesExtra;}		#die "@geneList\n";
	#my $tmpDir = $locTmpD;	system "mkdir -p  $tmpDir" unless(-d $tmpDir);	
	#	runCodeml(\@geneList, $treeFile, $codemlOutD, $MsaD, $tmpDir);   

	die;

}


#### fastgear ##
if($doFastGear){
	open I,"<$cogCats" or die "Can't open cogcats $cogCats\n"; 
		while (<I>){
			my $cnt3 =0;
			chomp; my @splF = split /\t/;
			@splF = grep !/^NA$/, @splF;#remove NAs
			if (@splF ==0){print "No categories in cat file line $cnt3\n";next;}
			$splF[0] =~ m/^(.*)$smplSep(.*)$/;					
			my @splF2 = ($1,$2);#split /$smplSep/,$spl[0] ;	
			#die "@spl\n";
			push(@geneListF, $splF2[1]);
			$cnt3 ++;
		}

	my $MsaDF1 = "$outD/MSA";
	#my $MsaDF2 = "$outD/MSA_FG";
	my $MsaDF2 = "$outD_clust/MSA_FG";
	my $MsaDF3 = ""; #added by Falk, debug, TODO!!
	system "mkdir $MsaDF3";		
	system "cp -r $MsaDF1 $MsaDF2";
	

	foreach my $geneF (@geneListF){
		my $outFG = "$outD/fastGear/fastGear_Results/$geneF";
		system "mkdir -p  $outFG" unless(-d "$outFG");
		my $outFileFG = "$outFG/${geneF}_res.mat";
		system "cat $MsaDF2/$geneF.*.fna | sed 's/_.*\$//' > $MsaDF2/$geneF.fna";
		my $FGparFile ="/g/bork3/home/luetge/softs/fastGEARpackageLinux64bit/fG_input_specs.txt";
		runFastgear($geneF, $outFileFG, $MsaDF2, $FGparFile);
	}
	system "rm -r $outD_clust";
	#die;
}
	


### postprocessing fastgear output ##
	
if($doFastGearSummary){
	my $FGDataD = "$outD/fastGear/";
	my $summaryD = "$FGDataD/fastGear_Summaries";
	system "mkdir -p  $summaryD" unless(-d "$summaryD");
	my $resultD = "$FGDataD/fastGear_Results";
	die "no fastgear results found\n" unless(-d $resultD);
		
	#die "$treeFileFG\n";
	my $allNamesFile ="$summaryD/allNamesFromTop.txt";
	my $treeNamesFile ="$summaryD/subtreeNamesFromTop.txt";
	
	# get a list with all genomes in tree
	if(! -e $allNamesFile |! -e $treeNamesFile){
		my @genomeListFG;		
		my @FNAheader_all = `grep '^>' $multAli`;
		#die "@FNAheader_all\n";
		foreach my $genome (@FNAheader_all){
			my ($genome2) = $genome =~ m/>(.*)?/;
			push (@genomeListFG, $genome2);
			}
		open T1,">$allNamesFile";
		print T1 join("\n",@genomeListFG);
		close T1;	
		#die;
		open T2,">$treeNamesFile";
		print T2 join("\n",@genomeListFG);
		close T2;
		#die "@genomeListFG\n";
	}

	# reorder files -> required for further steps?
	my $reorder_cmd = "$fastgearReorderBin $matlabBin $FGDataD fastGear_ allNamesFromTop.txt both";
	#die "$reorder_cmd\n";
	system $reorder_cmd; 
	
	## collect Recombination statistics #

	my $SRC_cmd = "$fastgearSummaryBin $matlabBin $FGDataD fastGear_";
	system $SRC_cmd; 
	print "fastgear collect recombination statistics finished";
	my $FG_sumOut = "$summaryD/fastGear__recSummaries.txt";
	if(-e $FG_sumOut){system "rm -rf $resultD";}
	#die;
}



	###################### ETE ######################3

print "All done: $outD \n\n";
exit(0);













##########################################################################################
##########################################################################################

sub mergePids($ $ $ $){
	my ($dir,$max,$seqType,$tag) = @_;
	#$outD/MSA/${seqType}_clustalo_percID_$cnt.txt
	#my $seqType = "AA";  
	opendir(DIR, $dir) or die $!;
    my @subfls  = grep { /$seqType.*_percID_.*\.txt/ } readdir(DIR); #_percID_.*\.txt
	close DIR;
	return if (@subfls == 0);
	#die "@subfls\n$dir\n";
	my %bigMat; my %bigCnt;
	for (my $j=0;$j<$max;$j++){
		my $disM = $subfls[$j]; #"$outD/MSA/${seqType}_clustalo_percID_$j.txt";
		$disM =~ m/_(\d+)\.txt$/;
		my $curL = $1;
		die "can't find distance matrix $dir$disM\n" unless (-e "$dir/$disM");
		my $cc=-2;
		my @IDS; my %cL;
		#print "$disM\n";
		open I ,"<$dir/$disM";
		while (my $line = <I>){
			$cc++;
			next if ($cc==-1);
			chomp $line;
			my @spl = split /\s+/,$line;
			my $id = shift @spl;
			push (@IDS,$id);
			$cL{$cc} = \@spl;
		}
		close I;
		system "rm $dir/$disM";
		#matrix in mem, now relate to actual dist matrix
		for (my $j=0;$j<@IDS;$j++){
			$IDS[$j] =~ m/([^_]+)_/;
			my $id1 = $1;
			for (my $k=$j;$k<@IDS;$k++){
				my $curPID = $cL{$j}[$k];
				$IDS[$k] =~ m/([^_]+)_/;
				my $id2 = $1;
				#print "$id1 $id2 $curPID\n";;
				$bigMat{$id1}{$id2} += $curPID * $curL;
				$bigCnt{$id1}{$id2} += $curL;
			}
		}
		#die;
	}
	my $oMat = "$dir/${seqType}${tag}_percID.txt";
	open O,">$oMat" or die "Can't open out dis mat $oMat\n";
	my @IDS = sort(keys %bigMat);
	print O "\t".join("\t",@IDS)."\n";
	for (my $j=0;$j<@IDS;$j++){
		my $id1 = $IDS[$j];
		print O $id1;
		for (my $k=0;$k<@IDS;$k++){
			my $id2 = $IDS[$k];
			if (exists($bigMat{$id1}{$id2} )){
				print O "\t".$bigMat{$id1}{$id2} / $bigCnt{$id1}{$id2};
			} elsif (exists($bigMat{$id2}{$id1} ) ) {
				print O "\t".$bigMat{$id2}{$id1} / $bigCnt{$id2}{$id1};
			} else {
				print O "\tNA"
				#die "$id1 $id2\n";
			}
		}
		print O "\n";
	}
	
	close O;
	#die $oMat;
}

#de novo aligns pairwise via vsearch and calcs id (iddef 2)
sub calcDisPos2($ $ $){
	my ($MSA,$opID, $isNT) = @_;
	my $vsBin  = getProgPaths("vsearch");
	my $swBin = getProgPaths("swipe");
	my $mkBldbBin = getProgPaths("makeblastdb");
	my $diaBin = getProgPaths("diamond");
	my $cmd="";
	$cmd = "$vsBin --threads $ncore --quiet --allpairs_global $MSA --acceptall --blast6out $tmpD/tmp.b6 --iddef 2 \n";
	my $prog = 0; #NT
	if ($isNT == 0){
		$prog = 1 ; #AA
#		$cmd = "$mkBldbBin -in $MSA -dbtype 'prot'\n";
#		$cmd .= "$swBin -p $prog -a $ncore -q $MSA  -d $MSA -c 0 -e 999 -m 0 -o $tmpD/tmp.b6  -b 9999999999999 \n" ;
		$cmd = "$diaBin makedb --in $MSA -d $MSA.db -p $ncore --quiet\n";
		$cmd .= "$diaBin blastp -f 6 -k 99999999 --min-score 0 --unal 1 --masking 0 --compress 0 --quiet -d $MSA.db -q $MSA -e 1e-4 --sensitive -o $tmpD/tmp.b6 -p $ncore\n";


		#die "$cmd\n";
	}
	#$cmd = $clustaloBin." -i $MSA -o $MSA.tmp --outfmt=fasta --percent-id --use-kimura --distmat-out $opID --threads=$ncore --force --full\n";
	#$cmd .= "rm -f $MSA.tmp\n";
	#die $cmd."\n";
	systemW $cmd;
	#die $cmd;
	my %perID;
	open I,"<$tmpD/tmp.b6" or die "Can't find $tmpD/tmp.b6\n";
	while (<I>){
		chomp;
		my @spl = split /\t/;
		#if (exists($perID{$spl[0]}{$spl[1]})){die "Entry in dis mat already exists: $spl[0] $spl[1]\n$cmd\n$tmpD/tmp.b6\n";}
		$perID{$spl[0]}{$spl[1]} = $spl[2];
		$perID{$spl[1]}{$spl[0]} = $spl[2];
	}
	close I;
	open O,">$opID" or die "Can't open dist mat output $opID\n";
	my @smpls = sort keys %perID;
	print O "percID\t".join("\t",@smpls)."";
	foreach my $k1 (@smpls){
		print O "\n$k1\t";
		foreach my $k2 (@smpls){
			if ($k1 eq $k2){print O "\t100";
			} else {
				if (!exists($perID{$k1}{$k2})){print O "\t0";}#die "Can;t locate keys $k1 $k2\n";}
				print O "\t".$perID{$k1}{$k2};
			}
		}
	}
	close O;
	unlink "$tmpD/tmp.b6";
	unlink "$MSA.db.dmnd" if (!$isNT);
	return 1;
}


#just get positions different between alignments, and their relative position
sub calcDiffDNA($ $){
	my ($MSA,$opID) = @_;
	my $kr = readFasta($MSA);
	my %MS = %{$kr};
	my $isNT = 1;
	my %diffArs;my %perID;
	print "Calculating distance matrix..\n";
	foreach my $k1 (keys %MS){
		$MS{$k1} = uc ($MS{$k1});
	}
	foreach my $k1 (keys %MS){
		my $ss1 = $MS{$k1};
		foreach my $k2 (keys %MS){
			next if ($k2 eq $k1);
			my $ss2 = $MS{$k2};
			my $mask = $ss1 ^ $ss2;
			my $diff=0;
			my$N2=($ss2 =~ tr/[-]//);
			my$N1=($ss1 =~ tr/[-]//);
			if ($isNT){
				$N1+=($ss1 =~ tr/[N]//);$N2+=($ss2 =~ tr/[N]//);
				while ($mask =~ /[^\0]/g) {
					my ($s1,$s2) = ( substr($ss1,$-[0],1),  substr($ss2,$-[0],1));#, ' ', $-[0], "\n";
					if ($s1 eq "-"){
						$N2++;next;
					}
					if ($s2 eq "-" ){#missing data, position doesn't matter
						$N1++;next;
					}
					$diffArs{$-[0]}=1;
					$diff++;
				}
			} else {
				while ($mask =~ /[^\0]/g) {
					my ($s1,$s2) = ( substr($ss1,$-[0],1),  substr($ss2,$-[0],1));#, ' ', $-[0], "\n";
					if ($s1 eq "N" ||$s1 eq "-"){
						$N2++;next;
					}
					if ($s2 eq "N" ||$s2 eq "-" ){#missing data, position doesn't matter
						$N1++;next;
					}
					$diffArs{$-[0]}=1;
					$diff++;
				}
			}
			my $nonDiff = ($mask =~ tr/[\0]//);
			$nonDiff -= $N1;
			$perID{$k1}{$k2}= $nonDiff/($diff+$nonDiff)*100;
		}
	}
	open O,">$opID" or die "Cant open out perc ID file $opID\n";
	my @smpls = keys %MS;
	print O "percID\t".join("\t",@smpls)."";
	foreach my $k1 (@smpls){
		print O "\n$k1\t";
		foreach my $k2 (@smpls){
			if ($k1 eq $k2){print O "\t100";
			} else {
				print O "\t".$perID{$k1}{$k2};
			}
		}
	}
	close O;
	my @NTdiffs = sort {$a <=> $b} (keys %diffArs);
	#die "Cant open out perc ID file $opID\n";
	my $MSAredF = $MSA; $MSAredF =~ s/\.[^\.]+$//;
	my $NSAposF = $MSAredF; $MSAredF.=".reduced.fna";
	$NSAposF .= ".reduced.pos";
	open O2,">$NSAposF" or die "Can't open reduced MSA position file $NSAposF\n";
	foreach my $i (@NTdiffs){
		print O2 "$i\n";
	} close O2;

	open O,">$MSAredF" or die "Can't open reduced MSA file $MSAredF\n";
	foreach my $k1 (@smpls){
		my $seq1 = $MS{$k1};
		my $seq = "";my $pos="";
		foreach my $i (@NTdiffs){
			$seq.=substr($seq1,$i,1);
			$pos .="$i\n";
		}
		print O ">$k1\n$seq\n";

	}
	close O;
	print "Dont calculating Distance matrix\n";
	#die "done\n";
}


sub calcDisPos($ $ $){
	my ($MSA,$opID, $isNT) = @_;
	#$cmd = $clustaloBin." -i $MSA -o $MSA.tmp --outfmt=fasta --percent-id --use-kimura --distmat-out $opID --threads=$ncore --force --full\n";
	#$cmd .= "rm -f $MSA.tmp\n";
	
	#too slow
	my $kr = readFasta($MSA);
	my %MS = %{$kr};
	my %diffArs;my %perID;
	print "Calculating distance matrix..\n";
	foreach my $k1 (keys %MS){
		$MS{$k1} = uc ($MS{$k1});
	}
	foreach my $k1 (keys %MS){
		my $ss1 = $MS{$k1};
		foreach my $k2 (keys %MS){
			next if ($k2 eq $k1);
			my $ss2 = $MS{$k2};
			my $mask = $ss1 ^ $ss2;
			my $diff=0;
			my$N2=($ss2 =~ tr/[-]//);
			my$N1=($ss1 =~ tr/[-]//);
			if ($isNT){
				$N1+=($ss1 =~ tr/[N]//);$N2+=($ss2 =~ tr/[N]//);
				while ($mask =~ /[^\0]/g) {
					my ($s1,$s2) = ( substr($ss1,$-[0],1),  substr($ss2,$-[0],1));#, ' ', $-[0], "\n";
					if ($s1 eq "-"){
						$N2++;next;
					}
					if ($s2 eq "-" ){#missing data, position doesn't matter
						$N1++;next;
					}
					$diffArs{$-[0]}=1;
					$diff++;
				}
			} else {
				while ($mask =~ /[^\0]/g) {
					my ($s1,$s2) = ( substr($ss1,$-[0],1),  substr($ss2,$-[0],1));#, ' ', $-[0], "\n";
					if ($s1 eq "N" ||$s1 eq "-"){
						$N2++;next;
					}
					if ($s2 eq "N" ||$s2 eq "-" ){#missing data, position doesn't matter
						$N1++;next;
					}
					$diffArs{$-[0]}=1;
					$diff++;
				}
			}
			my $nonDiff = ($mask =~ tr/[\0]//);
			$nonDiff -= $N1;
			$perID{$k1}{$k2}= $nonDiff/($diff+$nonDiff)*100;
		}
	}
	open O,">$opID" or die "Cant open out perc ID file $opID\n";
	my @smpls = keys %MS;
	print O "percID\t".join("\t",@smpls)."";
	foreach my $k1 (@smpls){
		print O "\n$k1\t";
		foreach my $k2 (@smpls){
			if ($k1 eq $k2){print O "\t100";
			} else {
				print O "\t".$perID{$k1}{$k2};
			}
		}
	}
	close O;
	my @NTdiffs = sort {$a <=> $b} (keys %diffArs);
	#die "Cant open out perc ID file $opID\n";
	my $MSAredF = $MSA; $MSAredF =~ s/\.[^\.]+$//;$MSAredF.=".reduced.fna";
	open O,">$MSAredF" or die "Can't open reduced MSA file $MSAredF\n";
	foreach my $k1 (@smpls){
		my $seq1 = $MS{$k1};
		my $seq = "";
		foreach my $i (@NTdiffs){
			$seq.=substr($seq1,$i,1);
		}
		print O ">$k1\n$seq\n";
	}
	close O;
	print "Dont calculating Distance matrix\n";
	#die "done\n";
}

sub mergeMSAs($ $ $ $){
	my ($MSAsAr,$samplesHr,$multAliF,$del) = @_;
	my @MSAs = @{$MSAsAr}; my %samples = %{$samplesHr};
	my %bigMSAFAAnxs;my %bigMSAFAA;foreach my $sm (keys %samples){$bigMSAFAA{$sm} ="";$bigMSAFAAnxs{$sm}="";}
	foreach my $MSAf (@MSAs){
		#print $MSAf."\n"; 
		my $hit =0; my $miss =0;
		my $hr = readFasta($MSAf,1); my %MFAA = %{$hr};
		system "rm $MSAf" if ($del);
		my @Mkeys = keys %MFAA;
		#die "$Mkeys[0]\n";
		
#		my @spl2 = split /$smplSep/,$Mkeys[0];
		$Mkeys[0] =~ m/^(.*)$smplSep(.*)$/;my @spl2 =($1,$2);
		my $gcat = $spl2[1];
		my $len = length( $MFAA{$Mkeys[0]} );
		#die $len;
		foreach my $sm (keys %samples){
			my $curK = $sm.$smplSep.$gcat; #print $curK. " ";
			#print "$MFAA{$curK}\n";
			if (exists $MFAA{$curK}){
				my $seq = $MFAA{$curK}; $hit++;
				$bigMSAFAA{$sm} .= $seq;
				$seq =~ s/^(-+)/"?" x length($1)/e;
				$seq =~ s/(-+)$/"?" x length($1)/e;
				#die $seq;
				$bigMSAFAAnxs{$sm} .= $seq;
			} else {
				$bigMSAFAA{$sm} .= "-"x$len; $miss++;#print "nooooooo ";
				$bigMSAFAAnxs{$sm} .= "?"x$len; $miss++;
			}
		}
		
		#die "$hit - $miss\n";
	}
	#filter part - count "-" in each seq
	
	my @ksMSAFAA = keys %bigMSAFAA;
	my $iniSeqNum = @ksMSAFAA; my $remSeqNum = 0;
	my %ntCnts; my $maxNtCnt=1;
	foreach my $kk (@ksMSAFAA){
		my $strCpy = $bigMSAFAA{$kk};
		my $num1 = $strCpy =~ tr/[\-N]//;
		#$num1++ while ($bigMSAFAA{$kk} !~ m/-/g);
		#now get actual num of bps
		$num1 = length($strCpy) - $num1;
		if ($num1 > $maxNtCnt){$maxNtCnt = $num1;}
		$ntCnts{$kk} = $num1;
	}
	foreach my $kk (@ksMSAFAA){
		my $num1 = $ntCnts{$kk};
		if ( ( ($num1 / $maxNtCnt ) < $ntFrac) || ($num1 < $ntCnt ) ){
			delete $bigMSAFAA{$kk}; delete $bigMSAFAAnxs{$kk}; $remSeqNum++; 
			print "$kk $num1  ".int($num1*1000 / ($maxNtCnt) )/1000 ." $ntFrac \n";
		}
		#print "$num1  $kk \n";#$bigMSAFAA{$kk}\n\n"; last;
	}
	open O,">$multAliF" or die "Can't open MSA outfile $multAliF\n";
	open O2,">$multAliF.nxs" or die "Can't open MSA nexus outfile $multAliF.nxs\n";
	my @allKs = keys %bigMSAFAA;
	print O2 "#NEXUS\nBegin data;\nDimensions ntax=".scalar(@allKs)." nchar=".length($bigMSAFAAnxs{$allKs[0]}).";\nFormat datatype=dna missing=? gap=-;\nMatrix\n";
	foreach my $kk (keys %bigMSAFAA){
		print O ">$kk\n$bigMSAFAA{$kk}\n";
		print O2 "\n$kk\t$bigMSAFAAnxs{$kk}";
	}
	print O2 "\n;\nend;";

	close O;close O2;
	#die "$multAliF\n";
	print "Removed $remSeqNum of $iniSeqNum sequences\n";
}
sub convertMultAli2NT($ $ $){
	my ($inMSA,$NTs,$outMSA) = @_;
	my $tmpMSA=0;
	if ($inMSA eq $outMSA){$outMSA .= ".tmp"; $tmpMSA=1;}
	my $cmd = "";
	#"$pal2nal $inMSA $NTs -output fasta -nostderr -codontable 11 > $outMSA\n";
	
	#$cmd = "$trimalBin -in $inMSA -out $outMSA -backtrans $NTs -keepheader -keepseqs -noallgaps -automated1 -ignorestopcodon\n";
	$cmd = "$trimalBin -in $inMSA -out $outMSA -backtrans $NTs -keepheader -ignorestopcodon  -gt 0.1 -cons 60\n";
	#die "$cmd\n$inMSA,$NTs,$outMSA\n";
	#my $hr1= readFasta($inMSA);
	#my %MSA = %{$hr1};
	#$hr1= readFasta($NTs);
	#my %NTs = %{$hr1};
	if ($tmpMSA){$cmd .= "rm $inMSA;mv $outMSA $inMSA;\n";}
	#print $cmd;
	#die "$cmd\n";
	die "Can't execute $cmd\n" if (system $cmd);
}

sub synPosOnlyAA($ $){#only leaves "constant" AA positions in MSA file.. 
#stupid, don't know if pal2nal can handle this.. prob not
	my ($inMSA,$outMSA) = @_;
	print "Syn";
	my $hr = readFasta($inMSA,1); my %FNA = %{$hr};
	my @aSeq = keys %FNA;
	my $len = length ($FNA{$aSeq[0]});
	for (my $i=0; $i< $len; $i+=3){
		my $cod = substr $FNA{$aSeq[0]},$i,3;
		my $iniAA = "A";
		for (my $j=1;$j<@aSeq;$j++){
		}
	}
	print " only\n";

}

sub synPosOnly{#now finished, version is cleaner
	my ($inMSA,$inAAMSA,$outMSA, $outMSAns, $ffold, $outgroup, $doSyn, $doNSyn) = @_;
	#print "Syn NT";
	my %convertor = (
    'TCA' => 'S', 'TCC' => 'S', 'TCG' => 'S', 'TCT' => 'S',    # Serine
    'TTC' => 'F', 'TTT' => 'F',    # Phenylalanine
    'TTA' => 'L', 'TTG' => 'L',    # Leucine
    'TAC' => 'Y',  'TAT' => 'Y',    # Tyrosine
    'TAA' => '*', 'TAG' => '*', 'TGA' => '*',    # Stop
    'TGC' => 'C', 'TGT' => 'C',    # Cysteine   
    'TGG' => 'W',    # Tryptophan
    'CTA' => 'L', 'CTC' => 'L', 'CTG' => 'L', 'CTT' => 'L',    # Leucine
    'CCA' => 'P', 'CCC' => 'P', 'CCG' => 'P', 'CCT' => 'P',    # Proline
    'CAC' => 'H', 'CAT' => 'H',    # Histidine
    'CAA' => 'Q', 'CAG' => 'Q',    # Glutamine
    'CGA' => 'R', 'CGC' => 'R', 'CGG' => 'R', 'CGT' => 'R',    # Arginine
    'ATA' => 'I', 'ATC' => 'I', 'ATT' => 'I',    # Isoleucine
    'ATG' => 'M',    # Methionine
    'ACA' => 'T', 'ACC' => 'T', 'ACG' => 'T', 'ACT' => 'T',    # Threonine
    'AAC' => 'N','AAT' => 'N',    # Asparagine
    'AAA' => 'K', 'AAG' => 'K',    # Lysine
    'AGC' => 'S', 'AGT' => 'S',    # Serine
    'AGA' => 'R','AGG' => 'R',    # Arginine
    'GTA' => 'V', 'GTC' => 'V', 'GTG' => 'V', 'GTT' => 'V',    # Valine
    'GCA' => 'A','GCC' => 'A', 'GCG' => 'A', 'GCT' => 'A',    # Alanine
    'GAC' => 'D', 'GAT' => 'D',    # Aspartic Acid
    'GAA' => 'E', 'GAG' => 'E',    # Glutamic Acid
    'GGA' => 'G','GGC' => 'G', 'GGG' => 'G', 'GGT' => 'G',    # Glycine
    );
	my %ffd;
	if ($ffold){ #calc 4fold deg codons in advance to real data
		foreach my $k (keys %convertor){
			my $subk = $k; my $iniAA = $convertor{$subk} ;
			my $cnt=0;
			foreach my $sNT ( ("A","T","G","C") ){
				
				substr ($subk,2,1) = $sNT;
				#print $subk ." " ;
				$cnt++ if ($convertor{$subk} eq $iniAA);
				
			}
#			if( $cnt ==4){ $ffd{$k} = 4;
#			} else {$ffd{$k} = 1;}
			if( $cnt ==4){ $ffd{$iniAA} = 4;
			} else {$ffd{$iniAA} = 1;}
		}
	}

	#assumes correct 3 frame for all sequences in inMSA
	my $hr = readFasta($inMSA,1); my %FNA = %{$hr};
	#my %FAA;
	#if (0  || !$ffold){
	#	$hr = readFasta($inAAMSA); %FAA = %{$hr};
	#}
	#print "$inMSA\n$inAAMSA\n$outMSA\n";
	my @aSeq = keys %FNA; 
	my %outFNA;#syn
	my %outFNAns;#non syn
	for (my $j=0;$j<@aSeq;$j++){$outFNA{$aSeq[$j]}="";}
	my $len = length ($FNA{$aSeq[0]});
	my $nsyn=0;my $syn=0;
	for (my $i=0; $i< $len; $i+=3){ #goes over every position
		my $j =0;
		my $iniAA = "-";
		while (1){ #check for first informative position
			my $iniCodon = substr $FNA{$aSeq[$j]},$i,3;
			if ($iniCodon =~ m/---/ || $iniCodon =~ m/N/){$j++; last if ($j >= @aSeq); next;}
			die "error: $iniCodon\n" if ($iniCodon =~ m/-/); #should not happen
			$iniAA = $convertor{$iniCodon};#substr $FAA{$aSeq[0]},$i,1; 
			last;
		}
		#die "$iniAA\n";
		my $isSame = 1;
		next unless (!$ffold || $ffd{$iniAA} == 4);
	#print $i." $iniAA ";
		for (;$j<@aSeq;$j++){
			if ($aSeq[$j] eq $outgroup){next;}#print "HIT   $aSeq[$j] eq $outgroup";
			my $newCodon = substr $FNA{$aSeq[$j]},$i,3;
			my $newAA = "-";
			if ($newCodon !~ m/-/ && $newCodon =~ m/[ACTG]{3}/i){
				die "Unkown AA $newCodon\n" unless (exists $convertor{$newCodon} );
				$newAA = $convertor{$newCodon} ; # substr $FAA{$aSeq[$j]},$i,1;
			} elsif ($newCodon =~ m/---/ || $newCodon =~ m/[NWYRSKMDVHB]/){
			} else {
				die "newCodon wrong $newCodon\n" ;
			}
			if ($iniAA ne $newAA && $newAA ne "-"){
				$isSame =0; last;
			}
		}
		if ($isSame){#add nts to file
			for (my $j=0;$j<@aSeq;$j++){
				if ($ffold){
					$outFNA{$aSeq[$j]} .= substr $FNA{$aSeq[$j]},($i)+2,1;
				} else {
					$outFNA{$aSeq[$j]} .= substr $FNA{$aSeq[$j]},$i,3;
				}
				#print substr $FNA{$aSeq[$j]},$i*3,3 . " ";
			}
			$syn++;
		} else {
			for (my $j=0;$j<@aSeq;$j++){
				$outFNAns{$aSeq[$j]} .= substr $FNA{$aSeq[$j]},$i,3;
			}
			$nsyn++;
		}
	}
	#die $inMSA."\n";
	if ($doSyn){
		if ($syn ==0){
			$outMSA = "";
		} else {
			open O ,">$outMSA" or die "Can't open outMSA $outMSA\n";
			for (my $j=0;$j<@aSeq;$j++){
				print O ">$aSeq[$j]\n$outFNA{$aSeq[$j]}\n";
			}
			close O;
		}
	}
	if ($doNSyn){
		if ($nsyn ==0){
			$outMSAns = "";
		} else {
			open O ,">$outMSAns" or die "Can't open outMSA $outMSAns\n";
			for (my $j=0;$j<@aSeq;$j++){
				print O ">$aSeq[$j]\n$outFNAns{$aSeq[$j]}\n";
			}
			close O;
		}
	}
	$aSeq[0] =~ m/^.*_(.*)$/;
	#die "$outMSA\n";
	print "$1 ($syn / $nsyn) ".@aSeq." seqs \n";
	#print " only\n";
	#print "\n";
	return ($outMSA,$outMSAns);
}



sub runCodeml($ $ $ $ $){
	my ($geneListRef, $nwkFile, $codemlOutD, $MSADir, $codemlOutDTmp) = @_;
	my @geneListFin = @{$geneListRef};
	my @omegaStart = @omegas;			
	
	my @FNAheader; my $nwkFile_gene; 
	foreach my $gene (@geneListFin){
		my $cnt = 0;
		my @genomeList;
				
		opendir(DIR, $MSADir);
		my @MSAfile = grep(/$gene.*\.fna/,readdir(DIR));
		closedir(DIR);
		#die "@MSAfile\n";
		
		my $MSAfile2 = "$MSADir/$MSAfile[0]";
		#die "$MSAfile2\n";

		open(FNA, "<$MSAfile2" ) or die "could not find $!";
		my @FNAheader = grep(/^>/, <FNA> );
		close FNA;		
		#die @FNAheader;

		foreach my $genome (@FNAheader){
			my ($genome2) = $genome =~ m/>(.*)?$smplSep/;
			push (@genomeList, $genome2);
			} 

		next if(scalar @genomeList <3);
		#die "@genomeList\n";
		#die "$nwkFile\n";
		
		my $codemlOutDFile = "$codemlOutD/${gene}_run2";
		system "mkdir -p  $codemlOutDFile" unless(-d $codemlOutDFile);
				
		$nwkFile_gene = "$codemlOutDTmp/subtree_$gene.nwk";

		####################### Prepare tree ################################## 
		my $cmd_prune = "python $eteBin mod -t $nwkFile --prune @genomeList --unroot -o $nwkFile_gene";
		#my $cmd_prune = "ete3 mod -t $nwkFile --prune @genomeList -o $nwkFile_gene";
		
		system $cmd_prune . "> $nwkFile_gene";
		#die;

		my $treeio = Bio::TreeIO->new(-file => $nwkFile_gene, -format => 'newick');
		my $nwkTree_all = $treeio->next_tree;
		my $nwkTree = $nwkTree_all->as_text('newick');
 
		foreach my $genom (@genomeList){
			$nwkTree =~ s/$genom/$genom\_$gene/g;
		}
		
		$nwkTree =~ s/\)1:/\):/g;
	
		my $nwkFile_gene2 = "$codemlOutDTmp/subtree2_$gene.nwk";
		open N, ">$nwkFile_gene2"; 
		print N $nwkTree;
		close N;


		####################################################################

		chdir $codemlOutDTmp;
		my $modelName;
		for (my $mod=0; $mod < scalar(@model); $mod++){		
			$modelName = $model[$mod];
			my @repSel;
			for (my $rep=1; $rep <= $repeatCounts; $rep++) {

				open M0,">$codemlOutDTmp/${gene}_${rep}_${modelName}.c" or die "Can't open control file for codeml: $gene\n";
		
				print M0 "seqfile = $MSAfile2\n";
				print M0 "verbose = 2\n";
				print M0 "treefile = $nwkFile_gene2\n";
				print M0 "outfile = $codemlOutDTmp/codemlOut_${gene}_${rep}_${modelName}.txt\n";
				print M0 "aaDist = 0\n";
				print M0 "fix_blength = 0\n";
				print M0 "runmode = 0\n";
				print M0 "seqtype = 1\n";
				print M0 "CodonFreq = 2\n";
				print M0 "clock = 0\n";
				print M0 "model = 0\n";
				print M0 "NSsites = $modelName\n";
				print M0 "fix_omega = 0\n";
				print M0 "omega = $omegaStart[($rep-1)]\n";
				print M0 "cleandata = 0\n";
				print M0 "getSE = 0\n";	
				print M0 "icode = 0\n";
				print M0 "fix_kappa = 0\n";
				print M0 "kappa = 2\n";
				print M0 "Mgene = 0\n";
				print M0 "ncatG = 8\n";
				print M0 "RateAncestor = 0\n";
				print M0 "Small_Diff = 1e-6\n";
				print M0 "noisy = 0\n";
				

				close M0;

				## run codeml  
				$cmd = "$pamlBin $codemlOutDTmp/${gene}_${rep}_${modelName}.c\n";			
				#die "$cmd\n";
				systemW $cmd; 
				print "finished codeml Model $modelName run $rep on $gene\n";
				#die;
				
				#get lnL and push to array
				open(CM, "<$codemlOutDTmp/codemlOut_${gene}_${rep}_${modelName}.txt" ) or die "could not find $!";
				while (my $line = <CM>) {
        				if ($line =~ /^lnL*/) {
            					$line =~ m/^.*\):\s*([-+]?[0-9]*\.?[0-9]+)\s.*$/;
						push @repSel, $1;
						last;
        				}				
				}
				close CM;
				#system "rm $codemlOutDTmp/rst1";

			} 
			
			my $idxMax = 0;
    			$repSel[$idxMax] > $repSel[$_] or $idxMax = $_ for 1 .. $#repSel; 
			my $repSelected = $idxMax+1;
			#die "@repSel\n$repSelected\n";
			system "cp $codemlOutDTmp/codemlOut_${gene}_${repSelected}_${modelName}.txt $codemlOutDFile/out_M$modelName.txt";
		}	
		
		system "rm -r $codemlOutDTmp";
		#system "rm $nwkFile_gene2";
		#system "rm $nwkFile_gene";
		#die;

	}


}

### Fastgear -> test for recombination 
sub runFastgear($ $ $ $){
	my ($geneFG, $outFile, $inD, $parFile) = @_;
	$cmd = "$fastgearBin $matlabBin $inD/$geneFG.fna $outFile $parFile";
	#die "$cmd\n";
	system $cmd; 
	print "fastgear on $geneFG finished";
	#die;
}

