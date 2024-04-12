#!/bin/bash
# $Id fieldfox_report.sh, v 1.0 2024/03/10 
# Copyright 2016-2024 Victor Giusti


wtitle="FieldFox CVS Report Generator - V 1.0"
configparam=$(tail -n +3 config.csv | cut -d ',' -f 1 | tr '\n' '!' | sed 's/.$//')

function show_error() {
    yad --title="Error!" \
        --image=dialog-error \
        --text="Si è verificato un errore. \n $1" \
        --button=gtk-ok:0
}

# Function to generate S21 plot
function plotil() {

gnuplot <<EOF
set terminal pngcairo size 1000,450 enhanced font 'Verdana,10'
set output '/tmp/S21.png'
set multiplot
set key ins vert
set key left top
set title  font ",12 norotate
set title "S21"
stats "/tmp/il.dat" u (\$1/1000000.):2 nooutput
set xrange [STATS_min_x:STATS_max_x]
set yrange [$ilplot:0.5]
set label 1 "Min" at STATS_pos_max_y, STATS_max_y 
set label 2 "Max" at STATS_pos_min_y, STATS_min_y 
set label 3 sprintf("Max = %3.2f db at %3.2f Mhz",STATS_max_y,STATS_pos_max_y) at graph 0.40,0.96
set label 4 sprintf("Min = %3.2f db at %3.2f Mhz",STATS_min_y,STATS_pos_min_y) at graph 0.73,0.96
set arrow from $startf, $illimit to $stopf, $illimit nohead ls 1 
set grid
set xlabel "Mhz"
set ylabel "dB"
set style line 1 lt 2 lc rgb "blue" lw 2
set style line 2 lt 2 lc rgb "orange" lw 1
plot '/tmp/il.dat' using (\$1/1000000.):2  w l t "S21" ls 1,\
     STATS_min_y w l  lc rgb "red" notitle, \
     STATS_max_y w l  lc rgb "green" notitle
plot '/tmp/il.dat' using (\$1/1000000.):2  smooth sbezier t "           AVG" ls 2
EOF
}

# Function to generate S11 plot
function plotrl() {

gnuplot <<EOF
set terminal pngcairo size 1000,450 enhanced font 'Verdana,10'
set output '/tmp/S11.png'
set multiplot
set key ins vert
set key left top
set title  font ",12 norotate
set title "S11"
stats "/tmp/rl.dat" u (\$1/1000000.):2 nooutput
set xrange [STATS_min_x:STATS_max_x]
set yrange [-60:0]
set label 1 "Max" at STATS_pos_max_y, STATS_max_y 
set label 2 "Min" at STATS_pos_min_y, STATS_min_y 
set label 3 sprintf("Max = %3.2f db at %3.2f Mhz",STATS_max_y,STATS_pos_max_y) at graph 0.40,0.96
set label 4 sprintf("Min = %3.2f db at %3.2f Mhz",STATS_min_y,STATS_pos_min_y) at graph 0.73,0.96
set arrow from $startf, $rllimit to $stopf, $rllimit nohead ls 1 
set grid
set xlabel "Mhz"
set ylabel "dB"
set style line 1 lt 2 lc rgb "blue" lw 2
set style line 2 lt 2 lc rgb "orange" lw 1
plot '/tmp/rl.dat' using (\$1/1000000.):2  w l t "S11" ls 1,\
     STATS_min_y w l  lc rgb "green" notitle, \
     STATS_max_y w l  lc rgb "red" notitle
plot '/tmp/rl.dat' using (\$1/1000000.):2  smooth sbezier t "           AVG" ls 2
EOF
}

# Function to generate report
function generatereport() {
    echo $reportinfo
    internalpn=$(echo $reportinfo | awk -F'|' '{print $1}')
    customer=$(echo $reportinfo | awk -F'|' '{print $2}')
    customerpn=$(echo $reportinfo | awk -F'|' '{print $7}')
    startf=$(echo $reportinfo | awk -F'|' '{print $3}')
    stopf=$(echo $reportinfo | awk -F'|' '{print $8}')
    illimit=$(echo $reportinfo | awk -F'|' '{print $4}')
    rllimit=$(echo $reportinfo | awk -F'|' '{print $5}')
    ilplot=$(echo $reportinfo | awk -F'|' '{print $9}')

    if [ "$newrep" = true ]; then
        echo "Save report config"
        il_limit=$(echo "$illimit" | sed 's/,/./')
        rl_limit=$(echo "$rllimit" | sed 's/,/./')
        echo "$internalpn,$customer,$customerpn,$startf,$stopf,$il_limit,$rl_limit,$ilplot" >> config.csv
    fi

    echo "generate report!"
    percent=$(echo "100 / $filecount" | bc )
    gauge=$percent

    #gor any sing csv file do...
    (   for datafile in $datadir/*.csv; do
            reportdtime=$(cat $datafile| grep "! TIMESTAMP" | cut -c12-50)
        	csplit --suppress-matched $datafile '/BEGIN/' '{*}' > /dev/null 2>&1
	        mv xx00 header 
        	head -n -5 xx01 | sed 's/,/   /g'  > /tmp/rl.dat 
	        head -n -1 xx02 | sed 's/,/  /g' >  /tmp/il.dat
	        filecsv=$(basename $datafile)
            filename="${filecsv%.*}"
            echo "# Generating PDF for: $filename"
            plotil
            plotrl
        	sed -e "s/INTERNALPN/$internalpn/g;s/TESTDATE/$reportdtime/g;s/FILENAME/$filename/g;s/CUSTOMERNAME/$customer/g;s/CUSTPN/$customerpn/g;s/STARTF/$startf/g;s/STOPF/$stopf/g;s/ILLIMIT/$illimit/g;s/RLLIMIT/$rllimit/g" templates/template_report.html > templates/tmp.html
	        wkhtmltopdf --log-level  info --enable-local-file-access  templates/tmp.html  $reportdir/RPT_$filename.pdf # 2> /dev/null
            echo "$gauge"
	        gauge=$(($gauge+$percent))
            rm xx01 xx02 header

        done
    ) | yad --title=$wtitle \
        --image="./images/dialog-apply.svg" \
        --progress --progress-text="Generating Report" --width=500 --percentage=0 \
        --auto-kill --auto-close  --enable-log="Generating Reports:" --log-expanded --log-height 500
        yad --title="Report generated!" \
        --image=dialog-info \
        --text="Report generated!!" \
        --button=gtk-ok:0
}

# Function gather report information
function inforeport {

	echo $reportdata
    datadir=$(echo $reportdata |awk -F "|" '{print $2}')
    internalpn=$(echo $reportdata |awk -F "|" '{print $1}')
    reportdir=$(echo $reportdata |awk -F "|" '{print $3}')

    if [ -z "$reportdir" ]; then
        show_error "Select Source report directory"
        exit 1
    fi

    if [ -z "$datadir" ]; then
        show_error "Select Destination Folder"
        exit 1
    else
        filecount=$(find $datadir -type f -name "*.csv" | grep -c "")
    fi
   
    if [[ $internalpn == *"NEW REPORT"* ]]; then
        echo "New report"
        customer="Customer Name"
        customerpn="Customer PN"
        startf=""
        stopf=""
        illimit="-1.0"
        rllimit="-20.82"
        ilplot="-10"
        newrep=true
    else
        echo "Load report"
        
        reportconfig=$(cat config.csv | grep $internalpn)
        customer=$(echo $reportconfig | awk -F',' '{print $2}')
        customerpn=$(echo $reportconfig | awk -F',' '{print $3}')
        startf=$(echo $reportconfig | awk -F',' '{print $4}')
        stopf=$(echo $reportconfig | awk -F',' '{print $5}')
        illimit=$(echo $reportconfig | awk -F',' '{print $6}')
        rllimit=$(echo $reportconfig | awk -F',' '{print $7}')
        ilplot=$(echo $reportconfig | awk -F',' '{print $8}')
        newrep=false
    fi

     
    reportinfo=$(yad --title="$wtitle" --center \
                --text="<span foreground='blue'><b><big><big>Found N°: $filecount data files\n\nReport Config:</big></big></b></span>" \
				--image=info \
				--form \
                --columns=2 \
				--field="<b><big>Internal P/N:</big></b>:CE" "^$internalpn" \
				--field="<b><big>Customer:    </big></b>:CE" "^$customer" \
                --field="<b><big>Start (f) Mhz:</big></b>:CE" "^$startf" \
                --field="<b><big>I/L Limit db:</big></b>:NUM" " $illimit!-30..1!0.1!1" \
                --field="<b><big>R/L Limit db:</big></b>:NUM" " $rllimit!-30..1!0.01!2" \
                --field=":LBL" "" \
                --field="<b><big>Customer P/N:</big></b>:CE" "^$customerpn" \
                --field="<b><big>Stop (f):</big></b>:CE" "^$stopf" \
                --field="<b><big>I/L PLot Limit:</big></b>:NUM" " $ilplot!-30..1!1" \
                --field=":LBL" "" \
				--button=gtk-close:99 \
				--button=gtk-ok:0)
				ret=$?

        case $ret in
			0|10) generatereport
			;;
			99) yad --center --image=stop --info --no-buttons --timeout 2 --text "<span foreground='red'><b><big><big>Report Canceled</big></big></b></span>" ; exit
			;;
			*) exit
	    esac
}

# Function for the main flow
function main {
    reportdata=$(yad --title="$wtitle" --center \
				--text="<span foreground='blue'><b><big><big>Report Information:</big></big></b></span>" \
				--image=info \
				--form \
				--field="<b><big>P/N: </big></b>:CB" "$configparam" \
				--field="<b><big>Data Files: </big></b>:MDIR" "" \
                --field="<b><big>Destination Folder: </big></b>:MDIR" "" \
				--button=gtk-close:99 \
				--button=gtk-ok:0)
				ret=$?
		
	  case $ret in
			0|10) echo "Save" ; inforeport
			;;
			99) yad --center --image=stop --info --no-buttons --timeout 2 --text "<span foreground='red'><b><big><big>Report Canceled</big></big></b></span>" ; exit
			;;
			*) exit
	   esac
}

# Execute the main function
main
