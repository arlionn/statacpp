capture program drop statacpp

/* 	changes from StataStan (stan.ado):
	modelfile -> codefile
	removed options: datafile, rerun, initsfile, load, diagnose, modesfile, chainfile,
		seed, chains, warmup, iter, thin, cmdstandir, mode, stepsize, stepsizejitter
	added options: standard
	
	output.csv -> output.do
	
	modelfile had 5-character extension like .stan but codefile has 4 like .cpp
	
	no need for wdir and cdir
	
	writing data is now inside an if!r(eof) loop 
	
	missing data are not allowed in Stan, so that was never a consideration, but 
		now we have to guard against them.
	
	matrices in R/S+ are read down the columns first, but in C++ are along the rows first.
*/

program define statacpp
version 11.0
syntax varlist [if] [in] [, CODEfile(string) ///
	INLINE THISFILE(string) STANDARD(string) ///
	OUTPUTfile(string) WINLOGfile(string) ///
	SKipmissing MATrices(string) GLobals(string) KEEPFiles]

/* options:
	codefile: name of C++ code file (that you have already saved)
		(following John Thompson's lead, if codefile=="", then look for
		a comment block in your do-file that begins with a line:
		"C++" and this will be written out as the model (omitting the 1st line)
	inline: read in the model from a comment block in this do-file
	thisfile: optional, to use with inline; gives the path and name of the
		current active do-file, used to locate the code inline. If
		thisfile is omitted, Stata will look at the most recent SD*
		file in c(tmpdir)
	standard: a string indicating the C++ standard to pass to the compiler. This has 
		to be one of: "98", "03", "11", "14", "gnu98", "gnu11" or "gnu14" (which are the
		g++ options, minus c++17 / c++1z)
	outputfile: name of do-file to contain output from executable 
	winlogfile: in Windows, where to store stdout & stderr before displaying on the screen
	skipmissing: omit missing values variablewise (caution required!!!)
	matrices: list of matrices to write, or 'all'
	globals: list of global macro names to write, or 'all'
	keepfiles: if stated, all files generated are kept in the working directory; if not,
		all are deleted except the C++ code and the executable.

Notes:
	As of version 0.1 (these things will be extended later): 
		we only use g++
		only numeric variables get written out
		returned data is passed via a do-file, but we could choose other formats too for dumping
		the user has to include somewhere in their int main() comments like this:
			// send global <globallist>
			// send matrix <matrixlist>
			// send var <varlist>
			They do not have to be together but there should only be one (or none)
				of each. There should be no tabs or spaces before the //. 
	
	non-existent globals and matrices, and non-numeric globals, get quietly ignored
	missing values are removed casewise by default
	users need to take care not to leave output file names as defaults if they
		have anything called output.csv etc. - these will be overwritten!
		
	#include<vector> is written to all pre-processor directives, and we could add others
	
	variables (in the Stata sense) get written as vectors, globals as atomic 
		variables (in the C++ sense), matrices get written as arrays. It is up to the 
		user to convert vectors to arrays inside the C++ code if they have a use for that.
	
	Only numeric data is written at present, string data will follow, and then dates (maybe!).
	C++ types int and double get utilised. Again, it is up to the user to convert in their 
		C++ code if they have reason to do so. globals and matrices are always written as double.
		If you want to get around this and have ints instead, save them as variables in the data
		with type int (in Stata) and then use the skipmissing option (although you may have to pad out 
		missing data in the
	
	g++ is the only compiler supported at present, and C++0x standard is required. We hope 
		to add more compilers, and will try to keep the standard as low as possible.
		
	we assume the codefile has a 4-character file extension like ".cpp" or ".cxx" or
	".hpp" and chop the last 4 chars off to make the execfile name

*/

local statacppversion="0.1"
local foundSends=0 // binary flag for writing outputfile later

// these will hold names of objects to return to Stata
local sendMatrix "" 
local sendVar ""
local sendGlobal ""

// display version 
dis as result "StataCpp version: `statacppversion'"

// defaults
if "`codefile'"=="" {
	local modelfile="statacpp.cpp"
}

if "`outputfile'"=="" {
	local outputfile="output" // this holds the entered name but .do will be appended later
}

if "`winlogfile'"=="" {
	local winlogfile="winlog.txt" // this only gets used in Windows
}
local lenmod=length("`codefile'")-4
local execfile=substr("`codefile'",1,`lenmod')
local deleteme="`execfile'"
if lower("$S_OS")=="windows" {
	local execfile="`deleteme'"+".exe"
}

if "`standard'"=="" {
	local standard "03"
}

if "`standard'"!="98" & "`standard'"!="03" & "`standard'"!="11" ///
	 & "`standard'"!="14" & "`standard'"!="gnu98" & "`standard'"!="gnu11" ///
	  & "`standard'"!="gnu14" {
		dis as error "standard option must be one of 98, 03, 11, 14, gnu98, gnu11 or gnu14"
		error 1
}

// strings to insert into shell command
if length("`standard'")==5 {
	local stdtemp = substr("`standard'",4,2)
	local standard = "-std=gnu++`stdtemp'"
}
else {
	local standard = "-std=c++`standard'"
}


// check for existing files
tempfile outputcheck
if lower("$S_OS")=="windows" {
	shell if exist "`outputfile'*.do" (echo yes) else (echo no) >> "`outputcheck'"
}
else {
	shell test -e "`outputfile'*.do" && echo "yes" || echo "no" >> "`outputcheck'"
}
file open oc using "`outputcheck'", read
file read oc ocline
if "`ocline'"=="yes" {
	dis as error "There are already one or more files called `outputfile'*.do"
	dis as error "These may be overwritten by statacpp or incorrectly read back into Stata."
	dis as error "Please rename or move them, or specify a different name in the outputfile option to avoid data loss or errors."
	capture file close oc
	error 1
}
capture file close oc

preserve
if "`if'"!="" | "`in'"!="" {
	keep `if' `in'
}

// drop missing data casewise ########### THIS PROBABLY NEEDS TO BE REMOVED ###########
if "`skipmissing'"!="skipmissing" {
	foreach v of local varlist {
		qui count if `v'!=.
		local nthisvar=r(N)
		qui drop if `v'==. & `nthisvar'>1
	}
}


// the capture block ensures the file handles are closed at the end, no matter what
capture noisily {

// inline (John Thompson's approach) model written to .cpp file
if "`inline'"!="" {
	tempname fin
	tempfile tdirls
	local tdir=c(tmpdir)
	// fetch temp do-file copy if no thisfile has been named
	if "`thisfile'"=="" {
		tempname lsin
		if lower("$S_OS")=="windows" {
			shell dir `tdir' -b -o:-D >> `tdirls'
		}
		else {
			shell ls `tdir' -t >>  `tdirls'
		}
		tempname lsin
		capture file close `lsin'
		file open `lsin' using `tdirls', read text
		// assumes there's nothing else on the 1st line
		file read `lsin' thisfile 
		if lower("$S_OS")=="windows" {
			local tempprefix="STD"
		}
		else {
			local tempprefix="SD"
		}
		while substr("`thisname'",1,2)!="`tempprefix'" {
			file read `lsin' thisname
			if lower("$S_OS")=="windows" {
				local thisfile "`tdir'\`thisname'"
			}
			else {
				local thisfile "`tdir'/`thisname'"
			}
			if r(eof)==1 {
				dis as error "Could not locate a do-file in the Stata temporary folder."
				dis as error "Try giving the path and file name with the 'thisfile' option"
				capture file close `lsin'
				error 1
			}
		}
		capture file close `lsin'

	}
	tempname fin
	capture file close `fin'
	file open `fin' using "`thisfile'" , read text
	file read `fin' line

	tokenize `"`line'"'
	local line1=`"`1'"'
	file read `fin' line
	tokenize `"`line'"'
	while (("`line1'"!="/*" | substr(`"`1'"',1,3)!="C++") & !r(eof)) {
		local line1="`1'"
		file read `fin' line
		tokenize `"`line'"'
	}
	if r(eof) {
		dis as error "Inline code not found. This should be one comment block beginning with: C++"
		capture file close `fin'
		error 1
	}

	tempname fout
	capture file close `fout'
	file open `fout' using "`codefile'" , write replace
	file write `fout' "`line'" _n
	file read `fin' line
	while ("`line'"!="*/") {
		file write `fout' "`line'" _n
		file read `fin' line
	}
	file close `fin'
	file close `fout'
}


// find location in cppfile to write data
tempname cppf // the handle for the codefile, to keep and use
tempfile cppf0 // a copy of it without data
tempname cppf0h // the handle for the copy without data
if lower("$S_OS")=="windows" {
	! copy "`codefile'" "`cppf0'"
}
else {
	! cp "`codefile'" "`cppf0'"
}
file open `cppf' using "`codefile'" , write replace
// required headers, no harm if duplicated by user
file write `cppf' "#include <iostream>" _n 
file write `cppf' "#include<array>" _n 
file write `cppf' "#include<vector>" _n 
file write `cppf' "#include <fstream>" _n 
file write `cppf' "#include <sstream>" _n 
file write `cppf' "using std::cout;" _n 
file write `cppf' "using std::endl;" _n 
file write `cppf' "using std::array;" _n 
file write `cppf' "using std::vector;" _n 
file write `cppf' "using std::ifstream;" _n 
file write `cppf' "using std::ofstream;" _n 

file open `cppf0h' using "`cppf0'", read 
file read `cppf0h' line
while (substr("`line'",1,8)!="int main" & !r(eof)) {
	file write `cppf' `"`macval(line)'"' _n
	file read `cppf0h' line
}
if r(eof) {
	dis as error "Start of the main function not found in `cppfile'. This should be a line starting: int main"
	capture file close `cppf'
	capture file close `cppf0h'
	error 1
}
else {
	file write `cppf' "`line'" _n // write the "int main() {" line
	// write data into cppfile
	// first, write out the data in Stata's memory
	// this can only cope with scalars (n=1) and vectors; matrices & globals are named in the option
	foreach v of local varlist {
		// determine variable type and allocate corresponding C++ type
		confirm numeric variable `v'
		capture confirm int variable `v'
		if !_rc {
			local vtype "int"
		}
		else {
			local vtype "double"
		} // this needs to be expanded to cope with strings
		local linenum=1
		qui count if `v'!=.
		local nthisvar=r(N)
		if `nthisvar'>1 {
			file write `cppf' "std::vector <`vtype'> `v' = {"
			if "`skipmissing'"=="skipmissing" {
				local nlines=0
				local i=1
				local linedata=`v'[`i']
				while `nlines'<`nthisvar' {
					if `linedata'!=. & `nlines'<(`nthisvar'-1) {
						file write `cppf' "`linedata', "
						local ++i
						local ++nlines
						local linedata=`v'[`i']
					}
					else if `linedata'!=. & `nlines'==(`nthisvar'-1) {
						file write `cppf' "`linedata'}" _n
						local ++nlines
					}

					else {
						local ++i
						local linedata=`v'[`i']
					}
				}
			}
			else {
				forvalues i=1/`nthisvar' {
					local linedata=`v'[`i']
					if `i'<`nthisvar' {
						file write `cppf' "`linedata', "
					}
					else {
						file write `cppf' "`linedata'};" _n
					}
				}
			}
		}
		else if `nthisvar'==1 {
			local linedata=`v'[1]
			file write `cppf' "`v' <- `linedata'" _n
		}
	}

	// write matrices
	if "`matrices'"!="" {
		if "`matrices'"=="all" {
			local matrices: all matrices
		}
		foreach mat in `matrices' {
			capture confirm matrix `mat'
			if !_rc {
				local mrow=rowsof(`mat')
				local mcol=colsof(`mat')
				if `mrow'==1 { // row matrix: write as vector
					if `mcol'==1 { // special case of 1x1 matrix: write as scalar
						local mval=`mat'[1,1]
						file write `cppf' "double `mat' = `mval';" _n
					}
					else {
						file write `cppf' "std::vector <double> `mat' = {"
						local mcolminusone=`mcol'-1
						forvalues i=1/`mcolminusone' {
							local mval=`mat'[1,`i']
							file write `cppf' "`mval',"
						}
						local mval=`mat'[1,`mcol']
						file write `cppf' "`mval'};" _n
					}
				}
				else if `mcol'==1 & `mrow'>1 { // column matrix: write as vector
					file write `cppf' "std::vector <double> `mat' = {"
					local mrowminusone=`mrow'-1
					forvalues i=1/`mrowminusone' {
						local mval=`mat'[`i',1]
						file write `cppf' "`mval',"
					}
					local mval=`mat'[`mrow',1]
					file write `cppf' "`mval'};" _n
				}
				else { // otherwise, write as matrix (rows first)
					file write `cppf' "double `mat'[`mrow'][`mcol'] = {"
					local mrowminusone=`mrow'-1
					local mcolminusone=`mcol'-1
					// write each row
					forvalues i=1/`mrowminusone' {
						file write `cppf' " { "
						forvalues j=1/`mcolminusone' {
							local mval=`mat'[`i',`j']
							file write `cppf' "`mval',"
						}
						// write last cell in that row
						local mval=`mat'[`i',`mcol']
						file write `cppf' "`mval' }, "						
					}
					// write final row
					file write `cppf' " { "
					forvalues j=1/`mcolminusone' { 
						local mval=`mat'[`mrow',`j']
						file write `cppf' "`mval',"
					}
					// write final cell
					local mval=`mat'[`mrow',`mcol']
					file write `cppf' "`mval' } };" _n
				}
			}
		}
	}
	// write globals
	if "`globals'"!="" {
		if "`globals'"=="all" {
			local globals: all globals
		}
		foreach g in `globals' {
			capture confirm number ${`g'}
			if !_rc {
				file write `cppf' "double `g' = ${`g'};" _n
			}
		}
	}
	
// carry on reading cppf0h and copying into cppf but look out for "// send ..."
	file read `cppf0h' line
	while (substr("`line'",1,8)!="int main" & !r(eof)) {
		if substr(`"`macval(line)'"',1,14)=="// send global" {
			// we will store these as a list of objects to write into a do-file
			local foundSends=1
			local sendGlobal=substr(`"`macval(line)'"',16,.)
		}
		if substr(`"`macval(line)'"',1,14)=="// send matrix" {
			local foundSends=1
			local sendMatrix=substr(`"`macval(line)'"',16,.)
		}
		if substr(`"`macval(line)'"',1,11)=="// send var" {
			local foundSends=1
			local sendVar=substr(`"`macval(line)'"',13,.)
		}
	// before writing rerturn statements, write the code to send back to Stata
	if substr(`"`macval(line)'"',1,6)=="return" {
		if `foundSends'==1 {
			file write `cppf' "ofstream wfile;" _n
			file write `cppf' `"`wfile.open("`outputfile'",ofstream::out);'"' _n
		}
		// write sendVar
		if "`sendVar'"!="" {
			foreach v in `sendVar' {
				file write `cppf' `"wfile << "input `v'" << endl;"' _n
				file write `cppf' "for(int i=0; i<=(`v'.size()-1); i++) {" _n
				file write `cppf' "wfile << `v'[i] << endl;" _n
				file write `cppf' "}" _n
				file write `cppf' `"wfile << "end" << endl;"' _n
			}
		}
		// write sendMatrix
		if "`sendMatrix'"!="" {
			foreach v in `sendMatrix' {
				file write `cppf' `"wfile << "input `v'" << endl;"' _n
				file write `cppf' "for(int i=0; i<=(`v'.size()-1); i++) {" _n
				file write `cppf' "wfile << `v'[i] << endl;" _n
				file write `cppf' "}" _n
				file write `cppf' `"wfile << "end" << endl;"' _n
			}
		}
		// write sendGlobal
		if "`sendGlobal'"!="" {
			foreach v in `sendGlobal' {
				file write `cppf' `"wfile << "input `v'" << endl;"' _n
				file write `cppf' "for(int i=0; i<=(`v'.size()-1); i++) {" _n
				file write `cppf' "wfile << `v'[i] << endl;" _n
				file write `cppf' "}" _n
				file write `cppf' `"wfile << "end" << endl;"' _n
			}
		}
		// close outputfile
		if `foundSends'==1 {
			file write `cppf' "wfile.close();" _n
		}

	}
	file write `cppf' `"`macval(line)'"' _n
	file read `cppf0h' line
	}

	capture file close `cppf'
	capture file close `cppf0h'
}
if lower("$S_OS")=="windows" {
	! del "`cppf0'"
}
else {
	! rm "`cppf0'"
}


restore

}



// Windows commands
if lower("$S_OS")=="windows" {
	// compile
	windowsmonitor, command(g++ "`codefile'" -o "`execfile'" -std=c++0x) ///
			winlogfile(`winlogfile') waitsecs(30)
			
	// run
	windowsmonitor, command("`execfile'") winlogfile(`winlogfile') waitsecs(30)
}


// Linux / Mac commands
else {
	// compile
	shell g++ "`codefile'" -o "`execfile'" -std=c++0x
	
	// run
	shell ./"`execfile'"
}


		

// do the outputfile to get the results in
do "`outputfile'"

// tidy up files
if lower("$S_OS")=="windows" {
	!del "`winlogfile'"
	!del "wmbatch.bat"
}
else {
	!rm "`winlogfile'"
	!rm "wmbatch.bat"
}
end

