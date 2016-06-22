#include <iostream>
#include<array>
#include<vector>
#include <fstream>
#include <sstream>
using std::cout;
using std::endl;
using std::array;
using std::vector;
using std::ifstream;
using std::ofstream;

int main() {
cout << "Now running the Fuel Efficiency Doubler (TM)" << endl;
int ncars = mpg.size();
vector<int> mpg2;
for(int i=0; i<=(ncars-1); i++) {
  mpg2.push_back(2*mpg[i]);
  cout << mpg2[i] << endl;
}
// send var mpg2
return 0;
}
