/* 
net from "https://raw.githubusercontent.com/sergiocorreia/stata-misc/master/"
cap ado uninstall block
net install block
*/

timer clear
timer on 1

do "~/git/statacpp/statacpp.ado"
cd "~/NYC taxi data"

/* 
C++
#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include <math.h>
#include <vector>
using std::cin;
using std::cout;
using std::cerr;
using std::endl;
using std::string;
using std::to_string; // this will require -std=c++11 when compiling
using std::stod;
using std::vector;
using std::ifstream;
using std::ofstream;
using std::stringstream;

int main(int argc, char *argv[]) {
  stringstream sarg;
  int k;
  sarg << argv[1];
  sarg >> k;
  string sk = to_string(k);
  string filename = argv[2]+sk+".csv";
  string results = argv[3]+sk+".csv";
  int countevery = 100000;
    if(argc>4) {
       sarg << argv[4];
       sarg >> countevery;
	}
    string line;
    string latstr;
    string longstr;
    int latbin;
    int longbin;
    std::size_t commapos;
    std::size_t latcomma;
    std::size_t longcomma;
    std::size_t endcomma;
	ifstream rfile;
    ofstream wfile;
    rfile.open(filename,ifstream::in);

    // NYC grid boundaries:
    int nycwest = -74263;
    int nyceast = -73700;
    int nycsouth = 40492;
    int nycnorth = 40919;
    int width = nyceast-nycwest;
    int height = nycnorth-nycsouth;

    // vectors to hold counts
    vector<int> latv (height*width);
    vector<int> longv (height*width);
    vector<int> countv (height*width);
    for(int i=0; i<width; i++) {
      for(int j=0; j<height; j++) {
        int v = j+(i*height);
        latv[v] = nycsouth+j;
        longv[v] = nycwest+i;
        countv[v] = 0; // ready to have rows added
      }
    }

    if(rfile) {
    int linecount=1;
    // get the header line out of the way
    getline(rfile,line);
    getline(rfile,line);
	while(!rfile.eof() && line!="") {
      if(linecount % countevery ==0) {
        cout << "Working on line " << linecount << endl;
      }

      line = line.substr(0,line.length()-1);

      commapos = 0;
      for(int ic=0; ic<9; ic++) {
        commapos = line.find(",",commapos+1);
      }
      commapos = line.find(",",commapos+1);
      longcomma = commapos;
      commapos = line.find(",",commapos+1);
      latcomma = commapos;
      commapos = line.find(",",commapos+1);
      endcomma = commapos;

      longstr = line.substr(longcomma+1,latcomma-longcomma-1);
      latstr = line.substr(latcomma+1,endcomma-latcomma-1);
      latbin = (double) (floor(stod(latstr)*10000))/10;
      longbin = (double) (floor(stod(longstr)*10000))/10;
      latbin = latbin-nycsouth;
      longbin = longbin-nycwest;

      // find relevant vector element and increment it
      if(latbin>=0 && latbin<height && longbin>=0 && longbin<width) {
        int v = latbin+(longbin*height);
        ++countv[v];
      }
      ++linecount;
      getline(rfile,line);
	}
    // write out results
    wfile.open(results,ofstream::out);
    wfile << "lat,long,count" << endl;
    for(int i=0; i<(height*width); i++) {
      int templat = latv[i];
      int templong = longv[i];
      int tempcount = countv[i];
      wfile << templat << "," << templong << "," << tempcount << endl;
    }
    rfile.close();
    wfile.close();
  }
  return 0;
}
*/

// run the binning for each month
statacpp, codefile("taxi-binning.cpp") cppargs("trip_data_ bin_ 100000") ///
	inline thisfile("/Users/robert/git/statacpp/statacpp-taxi-example.do") ///
	parallel(12)
	
	
// read in the counts for a lat/long grid
tempfile allcounts

forvalues k=1/12 {
import delimited "bin_`k'.csv", delimiters(",") clear varnames(nonames) rowrange(2)

replace v1 = v1/1000
replace v2 = v2/1000
replace v3=. if v3==0
rename v1 latitude
rename v2 longitude
rename v3 count

if `k'==1 {
	save "`allcounts'", replace
}
else {
	rename count count2
	merge 1:1 latitude longitude using "`allcounts'"
	replace count=count+count2
	drop count2
	drop _merge
	save "`allcounts'", replace
}
}

local split1 = 4
local split2 = 10
local split3 = 40
local split4 = 100
local split5 = 400
local split6 = 1000
local split7 = 4000
local split8 = 10000
local split9 = 40000

qui summ latitude
local minlat=r(min)
local maxlat=r(max)
qui summ longitude
local minlong=r(min)
local maxlong=r(max)

twoway (scatter latitude longitude if count<`split1', ///
				msymbol(point) mcolor(gs16) ///
				yscale(range(`minlat' `maxlat')) ///
				xscale(range(`minlong' `maxlong')) legend(off) ///
				graphregion(color(white))) ///
	   (scatter latitude longitude if count>=`split1' & count<`split2', msymbol(point) mcolor(gs15)) ///
	   (scatter latitude longitude if count>=`split2' & count<`split3', msymbol(point) mcolor(gs13)) ///
	   (scatter latitude longitude if count>=`split3' & count<`split4', msymbol(point) mcolor(gs11)) ///
	   (scatter latitude longitude if count>=`split4' & count<`split5', msymbol(point) mcolor(gs10)) ///
	   (scatter latitude longitude if count>=`split5' & count<`split6', msymbol(point) mcolor(gs8)) ///
	   (scatter latitude longitude if count>=`split6' & count<`split7', msymbol(point) mcolor(gs6)) ///
	   (scatter latitude longitude if count>=`split7' & count<`split8', msymbol(point) mcolor(gs4)) ///
	   (scatter latitude longitude if count>=`split8' & count<`split9', msymbol(point) mcolor(gs3)) ///
	   (scatter latitude longitude if count>=`split9' & count!=., msymbol(point) mcolor(black))
graph export "taxis.png", replace

save "nyc-taxis.dta", replace

timer off 1
timer list
timer clear
