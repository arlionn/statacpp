#include <iostream>
#include<array>
#include<vector>
using std::cout;
using std::endl;
using std::array;
using std::vector;
int main() {
cout << "Now running the Fuel Efficiency Doubler (TM)" << endl;
int ncars = mpg.size();
cout << ncars << endl;
vector<int> mpg2;
for(int i=0; i<=(ncars-1); i++) {
  mpg2.push_back(2*mpg[i]);
}
// send Stata mpg2
return 0;
}