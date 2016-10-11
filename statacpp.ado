capture program drop statacpp

/*
	Issues:
	outputcheck fails, echoing to stdout, if outputfile exists
*/

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
syntax [varlist] [if] [in] [, CODEfile(string) ///
	CPpargs(string) NCores(integer 1) PArallel(integer 1) ///
	INLINE THISFILE(string) STANDARD(string) ///
	OUTPUTfile(string) WINLOGfile(string) ///
	SKipmissing MATrices(string) GLobals(string) KEEPFiles]

/* 
Notes:
	As of version 0.2 (these things will be extended later): 
		we only use g++
		I have no intention of testing this in, or tweaking it for, Windows. Feel free to 
			contribute on GitHub. In theory it will work because it cannibalises StataStan 
			code... but practice is often rather different.
		only numeric variables get written out
		returned data is passed via a do-file, but we could choose other formats too for dumping
		the user has to include somewhere in their int main() comments like this:
			// send global <globallist>
			// send matrix <matrixlist>
			// send var <varlist>
			They do not have to be together but there should only be one (or none)
				of each. There should be no tabs or spaces before the //. 
		Any cases with missing data in a Stata variable which is sent to C++ will be removed (unless
			skipmissing is specified, in which case just that datum is removed, potentially making 
			a ragged array of data, which is OK because each Stata variable is passed as its own vector.
			If you really want to work with missing data in some way, you will have to code it in the
			old-fashioned way as 999 or some such, and then process it as you see fit inside C++.
	
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
	
	g++ is the only compiler supported at present, and C++11 standard is required. That's how I roll, 
		but I hope other fans of Stata and C++ will contribute on GitHub to add more compilers, 
		and I will try to keep the standard as low as possible (as in 0x, 11, 14..., not as in quality 
		of the work).
		
	we assume the codefile has a 4-character file extension like ".cpp" or ".cxx" or
	".hpp" and chop the last 4 chars off to make the execfile name

*/

local statacppversion="0.2"
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
	local outputfile="output.do" 
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
	local standard "11"
}

if "`standard'"!="98" & "`standard'"!="03" & "`standard'"!="11" ///
	 & "`standard'"!="14" & "`standard'"!="gnu98" & "`standard'"!="gnu11" ///
	  & "`standard'"!="gnu14" {
		dis as error "standard option must be one of 98, 03, 11, 14, gnu98, gnu11 or gnu14"
		error 1
}

if `parallel'<1 {
	dis as error "parallel option must have a positive integer"
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
	shell if exist "`outputfile'" (echo yes) else (echo no) >> "`outputcheck'"
}
else {
	shell test -e "`outputfile'" && echo "yes" || echo "no" >> "`outputcheck'"
}
file open oc using "`outputcheck'", read
file read oc ocline
if "`ocline'"=="yes" {
	dis as error "There are already one or more do-files called `outputfile'"
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

// drop missing data casewise 
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
	// check for the start of the code block
	while ((`"`line1'"'!="/*" | substr(`"`1'"',1,3)!="C++") & !r(eof)) {
		local line1="`1'"
		file read `fin' line
		tokenize `"`line'"'
	}
	if r(eof) {
		dis as error "Inline code not found. This should be one comment block beginning with: C++"
		capture file close `fin'
		error 1
	}
	// when the code block has been found:
		// open a file to receive the C++
	tempname fout
	capture file close `fout'
	file open `fout' using "`codefile'" , write replace
		// move on one line in the do-file
	local line1="`1'"
	file read `fin' line
	tokenize `"`line'"'
		// write out the block
	file write `fout' `"`line'"' _n
	file read `fin' line
	while (`"`line'"'!="*/") {
		file write `fout' `"`line'"' _n
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
while (substr(`"`line'"',1,8)!="int main" & !r(eof)) {
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
	file write `cppf' `"`line'"' _n // write the "int main() {" line
	// write data into cppfile
	// first, write out the data in Stata's memory
	// this can only cope with scalars (n=1) and vectors; matrices & globals are named in the option
	if "`varlist'"!="" {
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
			file write `cppf' "`v' <- `linedata'" _n // NEEDS TO BE CORRECTED
		}
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
	while (substr(`"`line'"',1,8)!="int main" & !r(eof)) {
		if substr(`"`macval(line)'"',1,14)=="// send global" {
			// we will store these as a list of objects to write into a do-file
			local foundSends=1
			local sendGlobal=substr(`"`macval(line)'"',16,.)
			dis as result "Attempting to return global(s) called `sendGlobal' to Stata"
		}
		if substr(`"`macval(line)'"',1,14)=="// send matrix" {
			local foundSends=1
			local sendMatrix=substr(`"`macval(line)'"',16,.)
			dis as result "Attempting to return matrix or matrices called `sendMatrix' to Stata"
		}
		if substr(`"`macval(line)'"',1,11)=="// send var" {
			local foundSends=1
			local sendVar=substr(`"`macval(line)'"',13,.)
			dis as result "Attempting to return var(s) called `sendVar' to Stata"
		}
	// before writing return statements, write the code to send back to Stata
	if substr(`"`macval(line)'"',1,6)=="return" {
		if `foundSends'==1 {
			file write `cppf' "ofstream wfile;" _n
			file write `cppf' `"wfile.open("`outputfile'",ofstream::out);"' _n
		}
		// write sendVar
		if "`sendVar'"!="" {
			foreach v in `sendVar' {
				file write `cppf' `"wfile << "input `v'" << endl;"' _n
				file write `cppf' "for(int i=0; i<=(`v'.size()-1); i++) {" _n
				file write `cppf' "wfile << `v'[i] << endl;" _n
				file write `cppf' "}" _n
				//file write `cppf' `"wfile << "end" << endl;"' _n
			}
		}
		// write sendMatrix
		// at present this assumes all matrices are arrays of doubles
		if "`sendMatrix'"!="" {
				file write `cppf' "int ncells; int ncols; int nrows;" _n
			foreach v in `sendMatrix' {
				file write `cppf' "ncells = sizeof(`v')/sizeof(double);" _n
				file write `cppf' "ncols = sizeof(`v'[0])/sizeof(double);" _n
				file write `cppf' "nrows = ncells/ncols;" _n
				file write `cppf' `"wfile << "matrix `v' = [";"' _n
				file write `cppf' "for(int i=0; i<nrows; i++) {" _n
				file write `cppf' "for(int j=0; j<ncols; j++) {" _n
				file write `cppf' `"wfile << `v'[i][j];"' _n
				file write `cppf' `"if(j<(ncols-1)) { wfile << ", "; }"'
				file write `cppf' "}" _n
				file write `cppf' `"if(i<(nrows-1)) { wfile << " \\ "; }"'
				file write `cppf' "}" _n
				file write `cppf' `"wfile << "]" << endl;"' _n
			}
		}		
		// write sendGlobal
		if "`sendGlobal'"!="" {
			foreach v in `sendGlobal' {
				file write `cppf' `"wfile << "global `v' = " << `v' << endl;"' _n
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
	windowsmonitor, command(g++ "`codefile'" -o "`execfile'" `standard') ///
			winlogfile(`winlogfile') waitsecs(30)
			
	// run
	windowsmonitor, command("`execfile'" `cppargs') winlogfile(`winlogfile') waitsecs(30)
}


// Linux / Mac commands
else {
	// compile
	shell g++ "`codefile'" -o "`execfile'" `standard'
	
	// run
	if `parallel'==1 {
		shell ./"`execfile'" `cppargs'
	}
	else {
		shell for i in {1..`parallel'}; do "./`execfile'" \$i `cppargs' & done
	}
}


		

// do the outputfile to get the results in
if `foundSends'==1 {
	capture qui do "`outputfile'"
}

// tidy up files
if lower("$S_OS")=="windows" {
	quietly {
		!del "`winlogfile'"
		!del "wmbatch.bat"
	}
}
else {
	quietly {
		!rm "`winlogfile'"
		!rm "wmbatch.bat"
	}
}
end

