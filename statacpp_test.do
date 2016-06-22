// test run for statacpp

clear all
sysuse auto
global myglob=123

// Opondo method
statacpp mpg, codefile

! rm myprog.cpp

// pre-written C++ file
statacpp mpg, codefile("myprog.cpp") globals("myglob")


// Thompson method

/* C++

*/




// Grant method

