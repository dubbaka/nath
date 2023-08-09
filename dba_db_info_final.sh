#!/usr/bin/env bash

#Author: Ranganath Reddy Dubbaka
#Date: 25-July-2023


# Set SCRIPT_DIR environment variable and create directory if not exist.
export SCRIPT_DIR=/home/oracle/nath/scripts

# Giving dummy sid values.
last_node_sid="'ONE TWO'"
export last_node_sid
last_node_db_names="'ONE TWO'"
export last_node_db_names

DBA="ranganath.dubbaka@franklintempleton.com"

# Capturing cluster node names.
cluster_nodes=$(ps -ef | grep tnslsnr | grep ASM | awk '{ print $8 }' | sed 's/tnslsnr/olsnodes/')
cluster_nodes=$($cluster_nodes)
cluster_nodes=$(echo $cluster_nodes | sed ':a;N;$!ba;s/\n/ /g')
cluster_name=$(ps -ef | grep tnslsnr | grep ASM | awk '{ print $8 }' | sed 's/tnslsnr/cemutlo/')
cluster_name=$($cluster_name -n)
host=$(hostname)
execution_node=$(echo $(hostname) | cut -d '.' -f1)

#DBA="ranganath.dubbaka@franklintempleton.com,VenkataChandraSekhar.Nallam@franklintempleton.com,prashantsukhadeo.patil@franklintempleton.com,narsireddy.perapola@franklintempleton.com"
body="Please review attachment for Database information that are currently running from Cluster: ${cluster_name}" 


#node1=$(echo $cluster_nodes | awk '{ print $1}')
rm -rf /tmp/database_info_$cluster_name.csv
touch /tmp/database_info_$cluster_name.csv

header='"Category","SubCategory","ClusterName","HostName","CDBName","PDBName","Env","Remarks","Inc_Count","Version","CPUs","TOTAL_RAM","CDB_SGA_HL","CDB_SGA_SL","CDB_PGA_HL","CDB_PGA_SL","CDB_Size","PDB_SGA_HL","PDB_SGA_SL","PDB_PGA_HL","PDB_PGA_SL","PDB_Size","Scan_name","DB_Ports","Services"'

echo $header > /tmp/database_info_$cluster_name.csv

echo "--------------------------------------------------------------------------------------------------------------------------------------------------------"
echo $header


# Looping cluster nodes to execute required script.
for node in $cluster_nodes
do

        # Using ssh executing the script on each cluster node.
        ssh $node -q 'bash -s' < dba_gen1_db_info.sh $last_node_sid $execution_node $last_node_db_names
        last_node_sid=$(echo $(ssh $execution_node -q 'cat /tmp/last_node_sid_values.txt'))
		last_node_db_names=$(echo $(ssh $execution_node -q 'cat /tmp/last_node_db_names.txt'))
        cat /tmp/cluster_info_$node.csv >> /tmp/database_info_$cluster_name.csv

done

# Removing temporary files as it is no longer needed.
ssh $execution_node -q 'rm -rf /tmp/last_node_sid_values.txt'
ssh $execution_node -q 'rm -rf /tmp/last_node_db_names.txt'
ssh $execution_node -q 'rm -rf /tmp/cluster_info_*.csv'

echo "--------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "Database details loaded to /tmp/database_info_$cluster_name.csv"
ls -l /tmp/database_info_$cluster_name.csv
cp /tmp/database_info_$cluster_name.csv /tmp/database_info_$cluster_name.csv.bak
echo $body | mailx -s "Database Information from Cluster - ${cluster_name}" -a "/tmp/database_info_$cluster_name.csv" "$DBA"
rm -rf /tmp/database_info_$cluster_name.csv
#End of Script