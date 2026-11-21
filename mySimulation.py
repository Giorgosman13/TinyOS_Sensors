#!/usr/bin/python

from TOSSIM import *
import sys, os
import random

t = Tossim([])
f = sys.stdout # Change to open('./logfile.txt', 'w') to save output to a file
SIM_END_TIME = 1000 * t.ticksPerSecond()

print "TicksPerSecond : ", t.ticksPerSecond(), "\n"

# Essential channels for your project
t.addChannel("Boot", f)
t.addChannel("Project", f)

# Uncomment these if you want full packet-by-packet debug logs:
# t.addChannel("SRTreeC", f)
# t.addChannel("Radio", f)

r = t.radio()
max_node_id = 0

# 1. Load topology and auto-detect node count
topo = open("topology.txt", "r")
for line in topo:
	s = line.split()
	if len(s) >= 3:
		u = int(s[0])
		v = int(s[1])
		gain = float(s[2])
		r.add(u, v, gain)
		if u > max_node_id:
			max_node_id = u
		if v > max_node_id:
			max_node_id = v
topo.close()

NUM_NODES = max_node_id + 1
print "Loaded topology with", NUM_NODES, "nodes."

# 2. Boot all nodes
offset = random.randint(0, 1023)
for i in range(0, NUM_NODES):
	m = t.getNode(i)
	m.bootAtTime(10 * t.ticksPerSecond() + offset + i)

# 3. Load noise model (capped at 100 lines for fast initialization)
mTosdir = os.getenv("TINYOS_ROOT_DIR")
noiseF = open(mTosdir + "/tos/lib/tossim/noise/meyer-heavy.txt", "r")
noise_lines = noiseF.readlines()[:100]
noiseF.close()

for line in noise_lines:
	str1 = line.strip()
	if str1:
		val = int(str1)
		for i in range(0, NUM_NODES):
			t.getNode(i).addNoiseTraceReading(val)

for i in range(0, NUM_NODES):
	t.getNode(i).createNoiseModel()

# 4. Run simulation
h = True
while h:
	try:
		h = t.runNextEvent()
	except:
		print sys.exc_info()

	if t.time() >= SIM_END_TIME:
		h = False
	if h <= 0:
		h = False

print "Simulation finished."