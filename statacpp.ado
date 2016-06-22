capture program drop statacpp

/* 	modelfile -> codefile
	removed options: datafile, rerun, initsfile, load, diagnose, modesfile, chainfile,
		seed, chains, warmup, iter, thin, cmdstandir, mode, stepsize, stepsizejitter
	added options: standard
	
	output.csv -> output.R
	
	modelfile had 5-character extension like .stan but codefile has 4 like .cpp
	
	no need for wdir and cdir
	
	writing data is now inside an if!r(eof) loop 
*/

program define statacpp
version 11.0
syntax varlist [if] [in] [, CODEfile(string) ///
	INLINE THISFILE(string) STANDARD(integer 3) ///
	OUTPUTfile(string) WINLOGfile(string) ///
	SKipmissing MATrices(string) GLobals(string) KEEPFiles]

/* options:
	codefile: name of C++ code file (that you have already saved)
		(following John Thompson's lead, if modelfile=="", then look for
		a comment block in your do-file that begins with a line:
		"C++" and this will be written out as the model (omitting the 1st line)
	inline: read in the model from a comment block in this do-file
	thisfile: optional, to use with inline; gives the path and name of the
		current active do-file, used to locate the code inline. If
		thisfile is omitted, Stata will look at the most recent SD*
		file in c(tmpdir)
	outputfile: name of file to contain output from executable in R/S+ format
	winlogfile: in Windows, where to store stdout & stderr before displaying on the screen
	skipmissing: omit missing values variablewise to Stan (caution required!!!)
	matrices: list of matrices to write, or 'all'
	globals: list of global macro names to write, or 'all'
	keepfiles: if stated, all files generated are kept in the working directory; if not,
		all are deleted except the C++ code and the executable.

Notes:
	As of version 0.1 (these things will be extended later): 
		we only use g++
		only numeric variables get written out
	
	non-existent globals and matrices, and non-numeric globals, get quietly ignored
	missing values are removed casewise by default
	users need to take care not to leave output file names as defaults if they
		have anything called output.csv etc. - these will be overwritten!
*/

local statacppversion="0.1"

// display version 
dis as result "StataCpp version: `statacppversion'"

// defaults
if "`codefile'"=="" {
	local modelfile="statacpp.cpp"
}
/* we assume the codefile has a 4-character file extension like ".cpp" or ".cxx" or
	".hpp" will chop the last 4 chars off to make the execfile name */

// this holds the entered name but .R will be appended later
if "`outputfile'"=="" {
	local outputfile="output"
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

// strings to insert into shell command
// need to add the standard here, maybe other stuff too

// check for existing files
tempfile outputcheck
if lower("$S_OS")=="windows" {
	shell if exist "`outputfile'*.R" (echo yes) else (echo no) >> "`outputcheck'"
}
else {
	shell test -e "`outputfile'*.R" && echo "yes" || echo "no" >> "`outputcheck'"
}
file open oc using "`outputcheck'", read
file read oc ocline
if "`ocline'"=="yes" {
	dis as error "There are already one or more files called `outputfile'*.R"
	dis as error "These may be overwritten by statacpp or incorrectly read back into Stata."
	dis as error "Please rename or move them, or specify a different name in the outputfile option to avoid data loss or errors."
	error 1
}
file close oc

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

// inline (John Thompson's approach) model written to .stan file
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
tempname cppf // the handle for the codefile to keep and use
tempname cppf0 // a copy of it without data
tempname cppf0h // the handle for the copy without data
if lower("$S_OS")=="windows" {
	! copy "`codefile'" "`cppf0'"
}
else {
	! cp "`codefile'" "`cppf0'"
}
file open `cppf' using "`codefile'" , write replace
file write `cppf' "#include<vector>" _n // required header, no harm if duplicated by user
file open `cppf0h' using "`cppf0'", read 
file read `cppf0h' line
while (substr("`line'",1,8)!="int main" & !r(eof)) {
	file write `cppf' `"`macval(line)'"' _n
	file read `cppf0h' line
}
if !r(eof) {
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
						file write `cppf' "`linedata')" _n
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
						file write `cppf' "`mat' <- `mval'" _n
					}
					else {
						file write `cppf' "`mat' <- c("
						local mcolminusone=`mcol'-1
						forvalues i=1/`mcolminusone' {
							local mval=`mat'[1,`i']
							file write `cppf' "`mval',"
						}
						local mval=`mat'[1,`mcol']
						file write `cppf' "`mval')" _n
					}
				}
				else if `mcol'==1 & `mrow'>1 { // column matrix: write as vector
					file write `cppf' "`mat' <- c("
					local mrowminusone=`mrow'-1
					forvalues i=1/`mrowminusone' {
						local mval=`mat'[`i',1]
						file write `cppf' "`mval',"
					}
					local mval=`mat'[`mrow',1]
					file write `cppf' "`mval')" _n
				}
				else { // otherwise, write as matrix
					file write `cppf' "`mat' <- structure(c("
					local mrowminusone=`mrow'-1
					local mcolminusone=`mcol'-1
					forvalues j=1/`mcolminusone' {
						forvalues i=1/`mrow' {
							local mval=`mat'[`i',`j']
							file write `cppf' "`mval',"
						}
					}
					forvalues i=1/`mrowminusone' { // write final column
						local mval=`mat'[`i',`mcol']
						file write `cppf' "`mval',"
					}
					// write final cell
					local mval=`mat'[`mrow',`mcol']
					file write `cppf' "`mval'), .Dim=c(`mrow',`mcol'))"
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
// carry on reading cppf0h and copying into cppf
	file read `cppf0h' line
	while (substr("`line'",1,8)!="int main" & !r(eof)) {
		file write `cppf' `"`macval(line)'"' _n
		file read `cppf0h' line
	}
}
else {
	dis as error "Start of the main function not found in `cppfile'. This should be a line starting: int main"
	capture file close `cppf'
	capture file close `cppf0h'
	error 1
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
end

/*#############################################################
######################## Windows code #########################
#############################################################*/
if lower("$S_OS")=="windows" {
	// unless re-running an existing compiled executable, move model to cmdstandir
	if "`rerun'"!="rerun" {
		// check if modelfile already exists in cdir
		capture confirm file "`cdir'\\`modelfile'"
		if !_rc {
			// check they are different before copying and compiling
			tempfile working
			shell fc /lb2 "`wdir'\\`modelfile'" "`cdir'\\`modelfile'" > "`working'"
			// if different shell copy "`wdir'\\`modelfile'" "`cdir'\\`modelfile'"
		}
		else {
			windowsmonitor, command(copy "`wdir'\\`modelfile'" "`cdir'\\`modelfile'") ///
				winlogfile(`winlogfile') waitsecs(30)
		}
	}
	else {
		windowsmonitor, command(copy "`wdir'\\`execfile'" "`cdir'\\`execfile'") ///
			winlogfile(`winlogfile') waitsecs(30)
	}

	! copy "`cdir'\`winlogfile'" "`wdir'\winlog1"
	cd "`cdir'"
	
	if "`rerun'"=="" {
		dis as result "###############################"
		dis as result "###  Output from compiling  ###"
		dis as result "###############################"
		windowsmonitor, command(make "`execfile'") winlogfile(`winlogfile') waitsecs(30)
	}
	! copy `cdir'\`winlogfile' `wdir'
	! copy "`cdir'\`cppfile'" "`wdir'\`cppfile'"
	! copy "`cdir'\`execfile'" "`wdir'\`execfile'"

	dis as result "##############################"
	dis as result "###  Output from sampling  ###"
	dis as result "##############################"

	if `chains'==1 {
		windowsmonitor, command(`cdir'\\`execfile' method=sample `warmcom' `itercom' `thincom' `seedcom' algorithm=hmc `stepcom' `stepjcom' output file="`wdir'\\`outputfile'.csv" data file="`wdir'\\`datafile'") ///
			winlogfile(`winlogfile') waitsecs(30)
	}
	else {
		windowsmonitor, command(for /l %%x in (1,1,`chains') do start /b /w `cdir'\\`execfile' id=%%x random `seedcom' method=sample `warmcom' `itercom' `thincom' algorithm=hmc `stepcom' `stepjcom' output file="`wdir'\\`outputfile'%%x.csv" data file="`wdir'\\`datafile'") ///
			winlogfile(`winlogfile') waitsecs(30)
	}
	! copy "`cdir'\`winlogfile'" "`wdir'\winlog3"
	! copy "`cdir'\`outputfile'*.csv" "`wdir'\`outputfile'*.csv"

	windowsmonitor, command(bin\stansummary.exe "`wdir'\\`outputfile'*.csv") winlogfile(`winlogfile') waitsecs(30)

	// reduce csv file
	if `chains'==1 {
		file open ofile using "`wdir'\\`outputfile'.csv", read
		file open rfile using "`wdir'\\`chainfile'", write text replace
		capture noisily {
			file read ofile oline
			while r(eof)==0 {
				if length("`oline'")!=0 {
					local firstchar=substr("`oline'",1,1)
					if "`firstchar'"!="#" {
						file write rfile "`oline'" _n
					}
				}
				file read ofile oline
			}
		}
		file close ofile
		file close rfile
	}
	else {
		local headerline=1 // flags up when writing the variable names in the header
		file open ofile using "`wdir'\\`outputfile'1.csv", read
		file open rfile using "`wdir'\\`chainfile'", write text replace
		capture noisily {
			file read ofile oline
			while r(eof)==0 {
				if length("`oline'")!=0 {
					local firstchar=substr("`oline'",1,1)
					if "`firstchar'"!="#" {
						if `headerline'==1 {
							file write rfile "`oline',chain" _n
							local headerline=0
						}
						else {
							file write rfile "`oline',1" _n
						}
					}
				}
				file read ofile oline
			}
		}
		file close ofile
		forvalues i=2/`chains' {
			file open ofile using "`wdir'\\`outputfile'`i'.csv", read
			capture noisily {
				file read ofile oline
				while r(eof)==0 {
					if length("`oline'")!=0 {
						local firstchar=substr("`oline'",1,1)
						// skip comments and (because these are chains 2-n)
						// the variable names (which always start with lp__)
						if "`firstchar'"!="#" & "`firstchar'"!="l" {
							file write rfile "`oline',`i'" _n
						}
					}
					file read ofile oline
				}
			}
			file close ofile
		}
		file close rfile
	}

	if "`mode'"=="mode" {
		dis as result "#############################################"
		dis as result "###  Output from optimizing to find mode  ###"
		dis as result "#############################################"
		windowsmonitor, command(`cdir'\\`execfile' optimize data file="`wdir'\\`datafile'" output file="`wdir'\\`outputfile'.csv") ///
			winlogfile(`winlogfile') waitsecs(30)

		// extract mode and lp__ from output.csv
		file open ofile using "`wdir'\\`outputfile'.csv", read
		file open mfile using "`wdir'\\`modesfile'", write text replace
		capture noisily {
			file read ofile oline
			while r(eof)==0 {
				if length("`oline'")!=0 {
					local firstchar=substr("`oline'",1,1)
					if "`firstchar'"!="#" {
						file write mfile "`oline'" _n
					}
				}
				file read ofile oline
			}
		}
		file close ofile
		file close mfile
		preserve
			insheet using "`wdir'\\`modesfile'", comma names clear
			local lp=lp__[1]
			dis as result "Log-probability at maximum: `lp'"
			drop lp__
			xpose, clear varname
			qui count
			local npars=r(N)
			forvalues i=1/`npars' {
				local parname=_varname[`i']
				label define parlab `i' "`parname'", add
			}
			encode _varname, gen(Parameter) label(parlab)
			gen str14 Posterior="Mode"
			tabdisp Parameter Posterior, cell(v1) cellwidth(9) left
		restore
	}

	if "`diagnose'"=="diagnose" {
		dis as result "#################################"
		dis as result "###  Output from diagnostics  ###"
		dis as result "#################################"
		windowsmonitor, command(`cdir'\\`execfile' diagnose data file="`wdir'\\`datafile'") ///
			winlogfile("`wdir'\\`winlogfile'") waitsecs(30)
	}

	// tidy up files
	!del "`winlogfile'"
	!del "wmbatch.bat"
	!del "`modelfile'"
	!copy "`cppfile'" "`wdir'\\`cppfile'"
	!copy "`execfile'" "`wdir'\\`execfile'"
	if "`keepfiles'"=="" {
		!del "`wdir'\\`winlogfile'"
		!del "`wdir'\\wmbatch.bat"
		!del "`wdir'\\`outputfile'*.csv"
	}
	!del "`cdir'\\`cppfile'"
	!del "`cdir'\\`execfile'"

	cd "`wdir'"
}

/*#######################################################
#################### Linux / Mac code ###################
#######################################################*/
else {
	// unless re-running an existing compiled executable, move model to cmdstandir
	if "`rerun'"!="rerun" {
		// check if modelfile already exists in cdir
		capture confirm file "`cdir'/`modelfile'"
		if !_rc {
			// check they are different before copying and compiling
			tempfile working
			shell diff -b "`wdir'/`modelfile'" "`cdir'/`modelfile'" > "`working'"
			tempname wrk
			file open `wrk' using "`working'", read text
			file read `wrk' line
			if "`line'" !="" {
				shell cp "`wdir'/`modelfile'" "`cdir'/`modelfile'"
			}
		}
		else {
			shell cp "`wdir'/`modelfile'" "`cdir'/`modelfile'"
		}
		shell cp "`wdir'/`modelfile'" "`cdir'/`modelfile'"
	}
	else {
		shell cp "`wdir'/`execfile'" "`cdir'/`execfile'"
	}
	cd "`cdir'"
	
	if "`rerun'"=="" {
		dis as result "###############################"
		dis as result "###  Output from compiling  ###"
		dis as result "###############################"
		shell make "`execfile'"
		// leave modelfile in cdir so make can check need to re-compile
		// shell rm "`cdir'/`modelfile'"
	}
	
	dis as result "##############################"
	dis as result "###  Output from sampling  ###"
	dis as result "##############################"
	if `chains'==1 {
		shell ./`execfile' random `seedcom' method=sample `warmcom' `itercom' `thincom' algorithm=hmc `stepcom' `stepjcom' output file="`wdir'/`outputfile'.csv" data file="`wdir'/`datafile'"
	}
	else {
		shell for i in {1..`chains'}; do ./`execfile' id=\$i random `seedcom' method=sample `warmcom' `itercom' `thincom' algorithm=hmc `stepcom' `stepjcom' output file="`wdir'/`outputfile'\$i.csv" data file="`wdir'/`datafile'" & done
	}
	shell bin/stansummary "`wdir'/`outputfile'*.csv"

	// reduce csv file
	if `chains'==1 {
		file open ofile using "`wdir'/`outputfile'.csv", read
		file open rfile using "`wdir'/`chainfile'", write text replace
		capture noisily {
			file read ofile oline
			while r(eof)==0 {
				if length("`oline'")!=0 {
					local firstchar=substr("`oline'",1,1)
					if "`firstchar'"!="#" {
						file write rfile "`oline'" _n
					}
				}
				file read ofile oline
			}
		}
		file close ofile
		file close rfile
	}
	else {
		local headerline=1 // flags up when writing the variable names in the header
		file open ofile using "`wdir'/`outputfile'1.csv", read
		file open rfile using "`wdir'/`chainfile'", write text replace
		capture noisily {
			file read ofile oline
			while r(eof)==0 {
				if length("`oline'")!=0 {
					local firstchar=substr("`oline'",1,1)
					if "`firstchar'"!="#" {
						if `headerline'==1 {
							file write rfile "`oline',chain" _n
							local headerline=0
						}
						else {
							file write rfile "`oline',1" _n
						}
					}
				}
				file read ofile oline
			}
		}
		file close ofile
		forvalues i=2/`chains' {
			file open ofile using "`wdir'/`outputfile'`i'.csv", read
			capture noisily {
				file read ofile oline
				while r(eof)==0 {
					if length("`oline'")!=0 {
						local firstchar=substr("`oline'",1,1)
						// skip comments and (because these are chains 2-n)
						// the variable names (which always start with lp__)
						if "`firstchar'"!="#" & "`firstchar'"!="l" {
							file write rfile "`oline',`i'" _n
						}
					}
					file read ofile oline
				}
			}
			file close ofile
		}
		file close rfile
	}

	if "`mode'"=="mode" {
		dis as result "#############################################"
		dis as result "###  Output from optimizing to find mode  ###"
		dis as result "#############################################"
		shell "`cdir'/`execfile'" optimize data file="`wdir'/`datafile'" output file="`wdir'/`outputfile'.csv"
		// extract mode and lp__ from output.csv
		file open ofile using "`wdir'/`outputfile'.csv", read
		file open mfile using "`wdir'/`modesfile'", write text replace
		capture noisily {
			file read ofile oline
			while r(eof)==0 {
				if length("`oline'")!=0 {
					local firstchar=substr("`oline'",1,1)
					if "`firstchar'"!="#" {
						file write mfile "`oline'" _n
					}
				}
				file read ofile oline
			}
		}
		file close ofile
		file close mfile
		preserve
			insheet using "`wdir'/`modesfile'", comma names clear
			local lp=lp__[1]
			dis as result "Log-probability at maximum: `lp'"
			drop lp__
			xpose, clear varname
			qui count
			local npars=r(N)
			forvalues i=1/`npars' {
				local parname=_varname[`i']
				label define parlab `i' "`parname'", add
			}
			encode _varname, gen(Parameter) label(parlab)
			gen str14 Posterior="Mode"
			tabdisp Parameter Posterior, cell(v1) cellwidth(9) left
		restore
	}
	if "`diagnose'"=="diagnose" {
		dis as result "#################################"
		dis as result "###  Output from diagnostics  ###"
		dis as result "#################################"
		shell "`cdir'/`execfile'" diagnose data file="`wdir'/`datafile'"
	}

		// tidy up files
	!rm "`winlogfile'"
	!rm "wmbatch.bat"
	!rm "`modelfile'"
	!cp "`cppfile'" "`wdir'/`cppfile'"
	!cp "`execfile'" "`wdir'/`execfile'"
	if "`keepfiles'"=="" {
		!rm "`wdir'/`outputfile'.csv"
	}
	!rm "`cdir'/`cppfile'"
	!rm "`cdir'/`execfile'"


	cd "`wdir'"
}

if "`load'"=="load" {
	dis as result "############################################"
	dis as result "###  Now loading Stan output into Stata  ###"
	dis as result "############################################"
	// read in output and tabulate
	insheet using "`chainfile'", comma names clear
	qui ds
	local allvars=r(varlist)
	gettoken v1 vn: allvars, parse(" ")
	while "`v1'"!="n_divergent__" {
		gettoken v1 vn: vn, parse(" ")
	}
	tabstat `vn', stat(n mean sd semean min p1 p5 p25 p50 p75 p95 p99)
	foreach v of local vn {
		qui centile `v', c(2.5 97.5)
		local cent025_`v'=r(c_1)
		local cent975_`v'=r(c_2)
		dis as result "95% CI for `v': `cent025_`v'' to `cent975_`v''"
	}
}

end
