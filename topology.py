import sys, math

D = int	(sys.argv[1])
R = float(sys.argv[2])

for i in range(D * D):
	x1, y1 = i // D, i % D 
	for j in range(i + 1, D * D):
		x2, y2 = j //D, j % D 

		if math.sqrt((x1 -x2) **2 + (y1-y2)**2) <= R:
			print(f"{i} {j} -50.0\n{j} {i} -50.0")