#!/usr/bin/env bash

#Author: Ranganath Reddy Dubbaka
#Date: 15-June-2024

if [[ $# -lt 2 || $# -gt 3 ]]
then
echo "Enter Correct Parameters"
echo "Please follow below paterns to make this script work"
echo "sh dba_runsql.sh ts.sql ALLCDBS	=> (this is to execute script on all CDB's with in cluster nodes)"
echo "sh dba_runsql.sh ts.sql ALLPDBS	=> (this is to execute script on all PDB's of all CDB's with in cluster nodes)"
echo "sh dba_runsql.sh ts.sql ALL		=> (this is to execute script on all CDB's and all of it PDBS's with in cluster nodes)"
echo "sh dba_runsql.sh ts.sql CDBNAME CDBONLY	 => (this is to execute script on specific CDB with in cluster nodes)"
echo "sh dba_runsql.sh ts.sql CDBNAME PDBNAME	 => (this is to execute script on specific PDB with in cluster nodes)"
echo "sh dba_runsql.sh ts.sql CDBNAME ALLPDBS	 => (this is to execute script on specific CDB's all of its PDBS with in cluster nodes)"
exit 1
fi


# Giving dummy sid values.
last_node_sid="'ONE TWO'"
export last_node_sid
last_node_db_names="'ONE TWO'"
export last_node_db_names

SCRIPT_DIR=/acfs02/oracle/nath/scripts/testing
LOG_DIR=$SCRIPT_DIR/log

DBA="ranganath.dubbaka@franklintempleton.com"

# Capturing cluster node names.
cluster_nodes=$(ps -ef | grep tnslsnr | grep ASM | awk '{ print $8 }' | sed 's/tnslsnr/olsnodes/')
cluster_nodes=$($cluster_nodes)
cluster_nodes=$(echo $cluster_nodes | sed ':a;N;$!ba;s/\n/ /g')
cluster_name=$(ps -ef | grep tnslsnr | grep ASM | awk '{ print $8 }' | sed 's/tnslsnr/cemutlo/')
cluster_name=$($cluster_name -n)
host=$(hostname)
execution_node=$(echo $(hostname) | cut -d '.' -f1)
script=$1
script_name=$(echo "$script" | cut -d '.' -f1)
execute_on=$2
execute_on_option=$3
logfile=$LOG_DIR/${script_name}_${execute_on}_$cluster_name.log


#node1=$(echo $cluster_nodes | awk '{ print $1}')
rm -rf $logfile

echo "CLUSTER_NODE: $cluster_nodes"

# Looping cluster nodes to execute required script.
for node in $cluster_nodes
do

        # Using ssh executing the script on each cluster node.
		if [ $# = 2 ]; then
        ssh $node -q 'bash -s' < $SCRIPT_DIR/runsql.sh $last_node_sid $execution_node $last_node_db_names $script $execute_on
		touch $logfile
		fi
		if [ $# = 3 ]; then
        ssh $node -q 'bash -s' < $SCRIPT_DIR/runsql.sh $last_node_sid $execution_node $last_node_db_names $script $execute_on $execute_on_option
		logfile=$LOG_DIR/${script_name}_${execute_on}_${execute_on_option}_$cluster_name.log
		touch $logfile
		fi		
        last_node_sid=$(echo $(ssh $execution_node -q 'cat /tmp/last_node_sid_values.txt'))
		last_node_db_names=$(echo $(ssh $execution_node -q 'cat /tmp/last_node_db_names.txt'))
        cat /tmp/runsql_server_$node.log >> $logfile

done

# Removing temporary files as it is no longer needed.
ssh $execution_node -q 'rm -rf /tmp/last_node_sid_values.txt'
ssh $execution_node -q 'rm -rf /tmp/last_node_db_names.txt'
ssh $execution_node -q 'rm -rf /tmp/runsql_server_*.log'

echo $(date "+DATE: %D TIME: %T")
echo $(date "+DATE: %D TIME: %T") >> $logfile
echo "----------------------------------------------------END-OF-FILE---------------------------------------------------------------"
echo "----------------------------------------------------END-OF-FILE---------------------------------------------------------------" >> $logfile

echo "Script execution log details loaded to $logfile"
ls -l $logfile
#echo $body | mailx -s "Script Execution log details from Cluster - ${cluster_name}" -a "$logfile" "$DBA"
#End of Script
