#!/usr/bin/python

import sys
import os

filename_dict = {10:"4k", 11:"8k", 12:"16k", 13:"32k", 14:"64k", 15:"128k", 16:"256k", 17:"512k", 18:"1m",
        19:"2m", 20:"4m", 21:"8m", 22:"16m", 23:"32m", 24:"64m", 25:"128m", 26:"256m", 27:"512m", 28:"1g"}

start = int(sys.argv[1])
end = int(sys.argv[2])

os.system("rm -rf eval_results/*")

for i in xrange(start, end+1):
  dir_name = "res_" + filename_dict[i]
  cmd = "mkdir eval_results/" + dir_name
  os.system(cmd)
  for j in [1]:
    prof_stat = "prof_res_" + filename_dict[i] + "_loop" + str(j) + ".stat"
    cmd0 = "./micro_bench --target=DIRECT " + str(i) + " " + str(j) + " | tee " + prof_stat
    cmd1 = "mv " + prof_stat + " eval_results/" + dir_name
    os.system(cmd0)
    os.system(cmd1)
    for k in xrange(1, 10):
      cmd3 = "./micro_bench --target=DIRECT " + str(i) + " " + str(j) + " >> eval_results/" + dir_name + "/" + prof_stat
      os.system(cmd3)
