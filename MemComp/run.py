"""

    Memory Compression Measurement program runner.
    A python script that automates calling to driver program
    and data gathering and parsing.

    By Yuqing Liu
    HEAP Lab, Virginia Tech 
    Jan 2020
    
"""

import os
import multiprocessing
import subprocess
import math

#edit this part or create "run_config.py"
flags = []      #additional flags for driver

#files to run
folders = []    #prior is not empty
files = []      #quits if both empty

compressions = []   #To compile
layouts = []        #To compile
                    #If both empty, compiles everything
interest = []   #Outputs to be processed
make_option = [] #extra flags for make
outputfile = "default.out"


driver = "./bin/driver"
threads = multiprocessing.cpu_count() + 1
path = os.path.dirname(os.path.abspath(__file__))

#reads a seperate file to potentially replace above run specs
if os.path.exists("run_config.py"):
    execfile("run_config.py")

of = open(outputfile, "w")
os.chdir(path)

p = subprocess.check_call(["make", "clean"])
if (len(compressions) + len(layouts) == 0):
    p = subprocess.check_call(["make", "-j"+str(threads)] + make_option + [ "default"])
else:
    p = subprocess.check_call(["make", "-j"+str(threads)] + make_option + [ "bootstrap", "driver"] + compressions + layouts)

output = []
index = 0
l = []
d = ""
if (len(folders) == 0):
    l = files
else:
    d = folders[0]
    l = os.listdir(d)
while True:
    l.sort()
    for f in [f for f in l if os.path.isfile(os.path.join(d, f))]:
        cmd = [driver, "-n", str(threads), "-f", os.path.join(d, f)] + flags
        print cmd
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
        o = p.communicate()[0]
        of.write(o)
        output.append(o)
        print f
        #lis = [[], []]
        #for i in o.split("\n"):
        #    if len(i) == 0:
        #        continue
        #    l1 = i.split(",")
        #    a = int(l1[0])
        #    b = int(l1[1])
        #    if b != 0: 
        #        b = int(math.log(b, 10)*50)
        #    else:
        #        b = 0
        #    c = int(l1[2])
        #    d1 = int(l1[3])
        #    f1 = 0
        #    if a == 0:
        #        #if d1 * 0.9 <= c:
        #    	    #continue
        #        f1 = 1- c/4096.0
        #    else:
        #        #if c * 0.9 <= d1:
        #    	    #continue
        #        f1 = 1- d1/4096.0
        #    while len(lis[a]) - 1 < b:
        #        lis[a].append(0)
        #    lis[a][b] = lis[a][b] + f1
        #a = len(lis[0])
        #if len(lis[1]) > a:
        #    a = len(lis[1])
        #for i in xrange(a):
        #    of.write(str(i)+",")
        #of.write("\n")
        #for i in lis[0]:
        #    of.write(str(i)+",")
        #of.write("\n")
        #for i in lis[1]:
        #    of.write(str(i)+",")
        #of.write("\n")
        #of.write("\n")
    #break
    print
    #sample data parsing part
    for j in interest:
        print j
        for i in output:
            lines = i.strip("\n").split("\n")
            if (len(lines) < 2):
                print i
                continue
            l0 = lines[0].strip(",").split(",")
            l1 = lines[1].strip(",").split(",")
            for k in xrange(len(l0)):
                if (l0[k] == j):
                    print l1[k]
                    break
        print
#
    output = []
    index = index + 1
    if (index >= len(folders)):
        break
    d = folders[index]
    l = os.listdir(d)
    of.write("\n")
of.close()