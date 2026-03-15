set terminal pdfcairo enhanced font 'Arial,16' size 5in,2.2in
set output 'mlptest.pdf'

# Axis labels
set xlabel "MLP" font "Arial,16" offset 0,0.5
set ylabel "Bandwidth (MB/s)" font "Arial,16" offset 1.5,0

# Tick labels
set xtics font "Arial,16"
set ytics font "Arial,16"
set style fill solid border -1
set style line 9 lt 1 lw 1 lc rgb "#dddddd"
set grid ytics ls 9 back

# Legend
set key font "Arial,14" outside center top  horizontal width -2 spacing 0.5 samplen 1.5

set lmargin 9
set bmargin 2.5

set xrange [1:16] 
set xtics 1,2,16
set xtics nomirror
set ytics nomirror

set logscale y
set yrange [100:30000]
set ytics (100, 200, 500, 1000, 2000, 5000, 10000, 20000)
set border lw 1.5

# Line styles
set style line 1 lt 1 lw 2 pt 9 ps 0.8 lc rgb "black"  # single bank 1c
set style line 2 lt 1 lw 2 pt 4 ps 1 lc rgb "black"  # single bank 4c
set style line 3 lt 1 lw 2 pt 9 ps 0.8 lc rgb "grey"  # all banks 1c
set style line 4 lt 1 lw 2 pt 4 ps 1 lc rgb "grey"  # all banks 4c

# Data separator
set datafile separator " "

# Plot using the first column from each file (ignoring the duplicate second column)
plot \
     'mlp-onebank-bw_corun0.dat' using 1:2 with linespoints ls 1 title '1×pll (SB)', \
     'mlp-onebank-bw_corun3.dat' using 1:2 with linespoints ls 2 title '4×pll (SB)', \
     'mlp-allbanks-bw_corun0.dat' using 1:2 with linespoints ls 3 title '1×pll (AB)', \
     'mlp-allbanks-bw_corun3.dat' using 1:2 with linespoints ls 4 title '4×pll (AB)'
