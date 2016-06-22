// test run for statacpp

clear all
sysuse auto
global myglob=123
mkmat weight length in 1/5, mat(mymat)

// Opondo method
statacpp mpg, codefile

! rm myprog.cpp

// pre-written C++ file
statacpp mpg, codefile("myprog.cpp") globals("myglob") matrices("mymat")


// Thompson method

/* C++

*/




// Grant method

