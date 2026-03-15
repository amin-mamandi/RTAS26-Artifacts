# --- Output settings ---
set terminal pdfcairo enhanced font 'Arial,14' size 4in,2.1in
set output 'platform_matmult_sdvbs_slowdown.pdf'

# --- Common settings ---
set datafile separator ","
set style data histogram
set style histogram cluster gap 1.5
#set style fill solid border -1
set style fill pattern border -1
set boxwidth 0.8 relative
set xtics rotate by -30
#set auto x

# Grayscale palette (inverted: light -> dark)
#set style line 1 lc rgb "#d9d9d9" lw 1   # all-banks read  (lightest gray)
#set style line 2 lc rgb "#b3b3b3" lw 1   # all-banks write (lighter gray)
#set style line 3 lc rgb "#808080" lw 1   # single banks read  (medium gray)
#set style line 4 lc rgb "black" lw 1   # single banks write (dark gray)
set lmargin 7
set rmargin 1
set tmargin 1
set bmargin 3

# Colors
set style line 12 lc rgb "grey" lw 1    # read
set style line 11 lc rgb "black" lw 1    # write

# Patterns
ALLBANK_PATTERN  = 9
ONEBANK_PATTERN  = 3

#unset key
set key  maxrows 1 font "Arial,12" at screen 0.80,1.01 width 1.5 spacing 1.2 samplen 1.5

set xtics nomirror
set xtics scale 0
set ytics nomirror

set grid ytics
set grid linewidth 0.5 linetype 1 linecolor rgb "#E0E0E0"

# --- Slowdown plot ---
set ylabel "Slowdown" font "Arial,14" offset 1.5,0
#set xlabel "Benchmarks"
set yrange [0:100]

# Count matmult entries (read lines) to place divider between the two groups
stats '< grep ",read," ./results/slowdown_matmult.csv' using 7 nooutput
nm = STATS_records


#set label "65.6 →" at 5.35, 47 left font "Arial,12" tc rgb "black"

# vertical divider style and placement (graph coords span full height)
set style arrow 10 nohead lc rgb "#808080" lw 1.5 dt 2
set arrow from nm-0.5, graph 0 to nm-0.5, graph 1 as 10

plot \
  '< cat ./results/slowdown_matmult.csv ./results/slowdown_sdvbs.csv | grep ",read,"' \
      using 7:xtic(1) title 'ABr' ls 12 fillstyle pattern ALLBANK_PATTERN, \
  '< cat ./results/slowdown_matmult.csv ./results/slowdown_sdvbs.csv | grep ",write,"' \
      using 7:xtic(1) title 'ABw' ls 11 fillstyle pattern ALLBANK_PATTERN, \
  '< cat ./results/slowdown_matmult_one.csv ./results/slowdown_sdvbs_one.csv | grep ",read,"' \
      using 7:xtic(1) title 'SBr' ls 12 fillstyle pattern ONEBANK_PATTERN, \
  '< cat ./results/slowdown_matmult_one.csv ./results/slowdown_sdvbs_one.csv | grep ",write,"' \
      using 7:xtic(1) title 'SBw' ls 11 fillstyle pattern ONEBANK_PATTERN, \
  1 with lines lc rgb "black" lw 1 dt 2 notitle