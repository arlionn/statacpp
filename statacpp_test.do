// test run for statacpp

clear all
do "~/git/statacpp/statacpp.ado"

cd "~/deleteme"
! rm myprog.cpp
! rm myprog
! rm output.do


/* ######################################################################
#######################    Correia method    ############################
#####   (the best all-rounder, requires the block command)   ############
###################################################################### */

net from "https://raw.githubusercontent.com/sergiocorreia/stata-misc/master/"
cap ado uninstall block
net install block

sysuse auto, clear
global myglob=2
mkmat weight length in 1/5, mat(mymat)

block, file("myprog.cpp") verbose
int main () {
cout << "Now running the Fuel Efficiency Boosterizer"  << endl;
cout << "We will multiply mpg by: " << myglob << endl;
std::vector <int> mpg2 = mpg;
for(int i=0;i<mpg.size();i++) {
mpg2[i] = mpg[i]*myglob;
}
double mymat2[1][2]= {{mymat[0][0], mymat[0][1]}};
// send var mpg2
// send matrix mymat2
return 0;
}
endblock

statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat") standard("11")



/* ##################################################################################
###############################    Opondo method    #################################
####  (visually unappealing but reliable; good practice for compound quotes!)  ######
################################################################################## */

sysuse auto, clear
global myglob=2
mkmat weight length in 1/5, mat(mymat)

tempname writecode
file open `writecode' using "myprog.cpp", write replace
// note the compound double quotes (cf http://www.stata.com/statalist/archive/2012-08/msg00924.html)
foreach line in ///
		"int main () { " ///
        `"cout << "Now running the Fuel Efficiency Boosterizer"  << endl; "' ///
		`"cout << "We will multiply mpg by: " << myglob << endl;"' ///
		"std::vector <int> mpg2 = mpg;" ///
		"for(int i=0;i<mpg.size();i++) {" ///
		"mpg2[i] = mpg[i]*myglob;" ///
		"}" ///
		"double mymat2[1][2]= {{mymat[0][0], mymat[0][1]}};" ///
		"// send var mpg2" ///
		"// send matrix mymat2" ///
		"return 0;" ///
		"}" {
	// note the compound double quotes (cf http://www.stata.com/statalist/archive/2012-08/msg00924.html)
	file write `writecode' `"`line'"' _n 
}
file close `writecode'


statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat") standard("11")




/* #########################################################################################
##############################    pre-written C++ file    ##################################
####  (totally reliable as long as you keep the latest .do with the latest .cpp ...)  ######
######################################################################################### */

sysuse auto, clear
global myglob=2
mkmat weight length in 1/5, mat(mymat)

statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat")




/* #####################################################################################
##############################    Thompson method    ###################################
####  (good but requires a strange hard-coding of the do-file name inside itself)  #####
######################################################################################## */

sysuse auto, clear
global myglob=2
mkmat weight length in 1/5, mat(mymat)

/* 
C++
int main () {
cout << "Now running the Fuel Efficiency Boosterizer"  << endl;
cout << "We will multiply mpg by: " << myglob << endl;
std::vector <int> mpg2 = mpg;
for(int i=0;i<mpg.size();i++) {
mpg2[i] = mpg[i]*myglob;
}
double mymat2[1][2]= {{mymat[0][0], mymat[0][1]}};
// send var mpg2
// send matrix mymat2
return 0;
}
*/
statacpp mpg, codefile("myprog.cpp") inline thisfile("~/git/statacpp/statacpp_test.do") ///
		globals("myglob") matrices("mymat")


		
		
/* #####################################################################################
###############################    Grant method    #####################################
####  (for the experienced / foolhardy user, tries to find the do-file in tmpdir)  #####
##################################################################################### */

sysuse auto, clear
global myglob=2
mkmat weight length in 1/5, mat(mymat)

/* 
C++
int main () {
cout << "Now running the Fuel Efficiency Boosterizer"  << endl;
cout << "We will multiply mpg by: " << myglob << endl;
std::vector <int> mpg2 = mpg;
for(int i=0;i<mpg.size();i++) {
mpg2[i] = mpg[i]*myglob;
}
double mymat2[1][2]= {{mymat[0][0], mymat[0][1]}};
// send var mpg2
// send matrix mymat2
return 0;
}
*/
statacpp mpg, codefile("myprog.cpp") inline globals("myglob") matrices("mymat")
