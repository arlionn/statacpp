#include <iostream>
using std::cout;
using std::endl;
int main() {
cout << "Now running the Fuel Efficiency Doubler (TM)" << endl;
int ncars = mpg.size();
std::array<int,ncars> mpg2;
for(int i=0; i<=ncars; i++) {
  mpg2[i] = 2*mpg[i];
}
// send Stata mpg2
return 0;
}
