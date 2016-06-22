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
std::vector <int> mpg = {22, 17, 22, 20, 15, 18, 26, 20, 16, 19, 14, 14, 21, 29, 16, 22, 22, 24, 19, 30, 18, 16, 17, 28, 21, 12, 12, 14, 22, 14, 15, 18, 14, 20, 21, 19, 19, 18, 19, 24, 16, 28, 34, 25, 26, 18, 18, 18, 19, 19, 19, 24, 17, 23, 25, 23, 35, 24, 21, 21, 25, 28, 30, 14, 26, 35, 18, 31, 18, 23, 41, 25, 25, 17};
double mymat[5][2] = { { 2930,186 },  { 3350,173 },  { 2640,168 },  { 3250,196 },  { 4080,222 } };
double myglob = 123;
cout << "Now running the Fuel Efficiency Doubler (TM)" << endl;
int ncars = mpg.size();
vector<int> mpg2;
for(int i=0; i<=(ncars-1); i++) {
  mpg2.push_back(2*mpg[i]);
  cout << mpg2[i] << endl;
}
// send var mpg2
ofstream wfile;

wfile << "input mpg2" << endl;
for(int i=0; i<=(mpg2.size()-1); i++) {
wfile << mpg2[i] << endl;
}
wfile << "end" << endl;
wfile << "input 0" << endl;
for(int i=0; i<=(0.size()-1); i++) {
wfile << 0[i] << endl;
}
wfile << "end" << endl;
wfile << "input 0" << endl;
for(int i=0; i<=(0.size()-1); i++) {
wfile << 0[i] << endl;
}
wfile << "end" << endl;
wfile.close();
return 0;
}
