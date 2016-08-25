// test run for statacpp

clear all
do "~/git/statacpp/statacpp.ado"

cd "~/deleteme"
! rm myprog.cpp
! rm myprog
! rm output.do

sysuse auto
global myglob=2
mkmat weight length in 1/5, mat(mymat)

// Opondo method
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

matrix A = [1,2,3 \ 4,5,6]
matrix list A


! rm myprog.cpp

// pre-written C++ file
statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat")


// Thompson method

/* C++

*/




// Grant method

