ssh-keygen -R 192.168.121.101
ssh-keygen -R 192.168.121.102
ssh-keygen -R 192.168.121.103
ssh-keygen -R 192.168.121.104
ssh-keygen -R 192.168.121.105
ssh-keygen -R 192.168.121.106

netlab status -i default --cleanup
netlab up 
