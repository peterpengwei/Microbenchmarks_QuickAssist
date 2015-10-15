#!/usr/bin/python

import sys
import os
from decimal import Decimal

filename_dict = {10:"4k", 11:"8k", 12:"16k", 13:"32k", 14:"64k", 15:"128k", 16:"256k", 17:"512k", 18:"1m",
        19:"2m", 20:"4m", 21:"8m", 22:"16m", 23:"32m", 24:"64m", 25:"128m", 26:"256m", 27:"512m", 28:"1g"}

start = int(sys.argv[1])
end = int(sys.argv[2])

group_list = [[], [], [], [], []]
group_list[0].append("I/O datasize")
group_list[1].append("Loop Number")
group_list[2].append("Preprocess")
group_list[3].append("Kernel")
group_list[4].append("Postprocess")

for i in xrange(start, end+1):
  dir_name = "res_" + filename_dict[i]
  for j in [1]:
    if (j == 1):
      group_list[0].append(filename_dict[i])
    else:
      group_list[0].append("")
    group_list[1].append(str(j))
    prof_stat = "prof_res_" + filename_dict[i] + "_loop" + str(j) + ".stat"
    stat_file = open("eval_results/" + dir_name + "/" + prof_stat)
    preprocess = Decimal("0.0")
    execution = Decimal("0.0")
    postprocess = Decimal("0.0")
    max_pre = Decimal("0.0")
    min_pre = Decimal('Inf')
    max_exe = Decimal("0.0")
    min_exe = Decimal('Inf')
    max_post = Decimal("0.0")
    min_post = Decimal('Inf')
    for line in stat_file:
      tokens = line.strip().split()
      if "one-time preprocess" in line:
        preprocess = preprocess + Decimal(tokens[2])
        max_pre = max_pre.max(Decimal(tokens[2]))
        min_pre = min_pre.min(Decimal(tokens[2]))
      if "kernel execution" in line:
        execution = execution + Decimal(tokens[2])
        max_exe = max_exe.max(Decimal(tokens[2]))
        min_exe = min_exe.min(Decimal(tokens[2]))
      if "one-time postprocess" in line:
        postprocess = postprocess + Decimal(tokens[2])
        max_post = max_post.max(Decimal(tokens[2]))
        min_post = min_post.min(Decimal(tokens[2]))
    group_list[2].append(str((preprocess-max_pre-min_pre)/Decimal("8.0")))
    group_list[3].append(str((execution-max_exe-min_exe)/Decimal("8.0")))
    group_list[4].append(str((postprocess-max_post-min_post)/Decimal("8.0")))
    stat_file.close()
output_file = open("final_stat.csv", 'w')
output_file.write(','.join(group_list[0]) + '\n')
output_file.write(','.join(group_list[1]) + '\n')
output_file.write(','.join(group_list[2]) + '\n')
output_file.write(','.join(group_list[3]) + '\n')
output_file.write(','.join(group_list[4]) + '\n')
output_file.close()
