// test run for statacpp

clear all
set obs 10
gen x=_n

/* C++

*/

// Opondo method
statacpp x, codefile

! rm myprog.cpp

// pre-written C++ file

// Thompson method

// Grant method

