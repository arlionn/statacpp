// test run for statacpp

clear all
do "C:\Users\ku52502\git\statacpp\statacpp.ado"

cd "C:\deleteme"
sysuse auto
global myglob=123
mkmat weight length in 1/5, mat(mymat)

// Opondo method
tempname writecode
file open `writecode' using "myprog.cpp", write replace
// in contrast to StataStan, you will need semicolons, so don't use them as delimiters
foreach line in ///
		"int main { " ///
        `"cout << "Hello world"  << endl; "' ///
		`"cout << "This is your global: " << myglob << endl;"' ///
		"}" {
	file write `writecode' `"`line'"' _n // note the compound double quotes (cf http://www.stata.com/statalist/archive/2012-08/msg00924.html)
}
file close `writecode'


statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat")

! rm myprog.cpp

// pre-written C++ file
statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat")


// Thompson method

/* C++

*/




// Grant method

