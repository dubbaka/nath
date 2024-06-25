#!/bin/bash

# Set Profile Environment.
. /home/oracle/.bash_profile

#functions to get SQL statement results

function set_db_env() {
db=$1
if [ -f $HOME/$db.env ]; then
	# Set database environment.
	source $HOME/$db.env > /dev/null 2>&1
fi
}

function get_db_sql_output() {
sql_result=$($ORACLE_HOME/bin/sqlplus -S /nolog << EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
set echo off
set feedback off
set heading off
set pages 0
$1;
exit;
EOF
)
echo "$sql_result"
}

function get_db_sql_result() {
sql_result=$($ORACLE_HOME/bin/sqlplus -S /nolog << EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
SET TRIMSPOOL ON
SET TIMING ON
spool $1.log
select to_char(sysdate,'DD-MON-YYYY hh24:mi:ss') as START_DATE_TIME from dual;
select db_unique_name,i.instance_name INSTANCE_NAME from v\$database,v\$instance i;
@$1;
select to_char(sysdate,'DD-MON-YYYY hh24:mi:ss') as END_DATE_TIME from dual;
spool off
exit;
EOF
)
echo "$sql_result"
}

function get_pdb_sql_result() {
sql_result=$($ORACLE_HOME/bin/sqlplus -S /nolog << EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
alter session set container = $2;
SET TRIMSPOOL ON
SET TIMING ON
spool $1.log
col PDB_NAME for a20;
select to_char(sysdate,'DD-MON-YYYY hh24:mi:ss') as START_DATE_TIME from dual;
select d.db_unique_name,i.instance_name INSTANCE_NAME, p.name as PDB_NAME,p.open_mode from v\$database d,v\$pdbs p,v\$instance i;
@$1;
select to_char(sysdate,'DD-MON-YYYY hh24:mi:ss') as END_DATE_TIME from dual;
spool off
exit;
EOF
)
echo "$sql_result"
}

function get_db_list() {
dblist=$(ps -ef | grep pmon | grep -v grep | grep -v + | awk '{ print $8 }' | cut -d '_' -f3 | sed 's/[0-9]$//')
echo "$dblist"
}

function get_instance_list() {
instances=$(ps -ef | grep pmon | grep -v grep | grep -v + | awk '{ print $8 }' | cut -d '_' -f3)
echo "$instances"
}

function get_short_hostname() {
host=$(hostname)
host=$(echo $(hostname) | cut -d '.' -f1)
echo "$host"
}

function get_datetime () {
date_time=$(date "+DATE: %D TIME: %T")
echo "$date_time"
}

sysdate=$(date "+%Y%m%d%H")

SCRIPT_DIR=/acfs02/oracle/nath/scripts/testing
LOG_DIR=$SCRIPT_DIR/log
script=$(echo "$SCRIPT_DIR/$4")
script_name=$4
script_name=$(echo "$script_name" | cut -d '.' -f1)
execute_on=$5
execute_on_pdb=$6
host=$(hostname)
node=$(echo $(hostname) | cut -d '.' -f1)

# Removing and re-creating runsql_server_$node.log file.
rm -rf /tmp/runsql_server_$node.log
touch /tmp/runsql_server_$node.log

# Assiging parameter value after removing single codes.
last_node_sid=$(echo $1 | sed "s/'//g")
execution_node=$2
last_node_db_names=$(echo $3 | sed "s/'//g")



	# SQL statements that are needed to get required values
	open_mode_sql="select open_mode from v\$database"
	db_name_sql="select name from v\$database"
	container_sql="select nvl(cdb,'NO') from v\$database"
	pdbs_sql="select name from v\$pdbs where name NOT IN ('PDB\$SEED') and  name NOT LIKE '%PDB1'"
	

	db_list=$(get_db_list)
	cdb_parameter_options=("ALLCDBS" "allcdbs" "ALL" "all")
	pdb_parameter_options=("ALLPDBS" "allpdbs" "ALL" "all")


	if [[ ${cdb_parameter_options[@]} =~ $execute_on || ${pdb_parameter_options[@]} =~ $execute_on ]]
	then
		db_list=$(get_db_list)
	else
		db_list=$execute_on
	fi
	
	instances=$(get_instance_list)
	host=$(get_short_hostname)
		
	for db in $db_list
	do

		echo "------------------------------------------------------------------------------------------------------------------" >> /tmp/runsql_server_$node.log
		echo "------------------------------------------------------------------------------------------------------------------" 
		echo "Executing on ( Database:$db Server:$node )" >> /tmp/runsql_server_$node.log
		echo "Executing on ( Database:$db Server:$node )" 
    
		# Check if this database already connected and eexecuted script, this condition will filter duplicates.
		if echo "${last_node_sid[@]}" | grep -qv "$db";
		then
			if [ -f $HOME/$db.env ]; then
			
				# Set database environment.
				source $HOME/$db.env > /dev/null 2>&1
				open_mode=$(get_db_sql_output "${open_mode_sql}")
		
				#Check if the database in not opened.
				if [[ "${open_mode[*]} " =~ "ORA-01507" ]]; then
					echo "Database: $db not mounted" >> /tmp/runsql_server_$node.log
					echo "Database: $db not mounted" 
					
				else

					db_name=$(get_db_sql_output "${db_name_sql}")
					if echo "${last_node_db_names[@]}" | grep -qv "$db_name"; then
				
						container=$(get_db_sql_output "${container_sql}")
						if [[ $container = "YES" ]]
						then
						
							if [[ $# = 6 && $execute_on_pdb != "ALLPDBS" && $execute_on_pdb != "CDBONLY"  ]]; then
								pdbs=$execute_on_pdb
								execute_on_pdb="ALLPDBS"
							else
								pdbs=$(get_db_sql_output "${pdbs_sql}")
								
							fi
							
							#echo "PDB List: $pdbs"
							for pdb in $pdbs
							do
								if [[ ${pdb_parameter_options[@]} =~ $execute_on || ($execute_on_pdb=$pdb && ${pdb_parameter_options[@]} =~ $execute_on) || $execute_on_pdb = "ALLPDBS" ]]
								then
								echo ""
								echo "******************************************************************************************************************" >> /tmp/runsql_server_$node.log
								echo "******************************************************************************************************************"
								echo "Executing ${script} script on PDB : $pdb" >> /tmp/runsql_server_$node.log
								get_pdb_sql_result "${script}" "${pdb}"
								#script_name=$(echo "$script_name" | cut -d '.' -f1)
								cat ${script}.log >> /tmp/runsql_server_$node.log
								mv ${script}.log $LOG_DIR/${script_name}_${db}_${pdb}_${sysdate}.log
								fi
							done
							if [[ ${cdb_parameter_options[@]} =~ $execute_on  || $execute_on_pdb = "CDBONLY" ]]
							then
								echo ""
								echo "==================================================================================================================" >> /tmp/runsql_server_$node.log
								echo "=================================================================================================================="							
								echo "Also executing ${script} script on Container : $db" >> /tmp/runsql_server_$node.log
								get_db_sql_result "${script}"
								#script_name=$(echo "$script_name" | cut -d '.' -f1)
								cat ${script}.log >> /tmp/runsql_server_$node.log
								mv ${script}.log $LOG_DIR/${script_name}_${db}_${sysdate}.log
							fi
							
						else
							echo "Executing ${script} script on Container : $db" >> /tmp/runsql_server_$node.log
							get_db_sql_result "${script}"
							#script_name=$(echo "$script_name" | cut -d '.' -f1)
							cat ${script}.log >> /tmp/runsql_server_$node.log
							mv ${script}.log $LOG_DIR/${script_name}_${db}_${sysdate}.log
						fi
					else
					
						echo "(Instance Name:$db) or (Environment file:$db.env) not matching with DB_NAME:$db_name) Please check" >> /tmp/runsql_server_$node.log
						echo "ERROR: Environment file:$db.env not matching with DB_NAME:$db_name" >> /tmp/runsql_server_$node.log
						echo "ERROR: Environment file:$db.env not matching with DB_NAME:$db_name" 
					fi
				fi
			else
				echo "Environment file $HOME/$db.env file doesn't exist" >> /tmp/runsql_server_$node.log
				echo "Environment file $HOME/$db.env file doesn't exist" 				
			fi
		else
			echo "Script already executed on one of the instance of: $db, So Skipping it." >> /tmp/runsql_server_$node.log
			echo "Script already executed on one of the instance of: $db, So Skipping it."
		fi
		#appending db_names
		last_node_db_names=$(echo "'$last_node_db_names $db_name'")
		last_node_db_names=$(echo $last_node_db_names | sed "s/'//g")

	done

	#copy final csv file to node1 /tmp location
	if [[ $node != $execution_node ]]; then
		scp -q /tmp/runsql_server_$node.log ${execution_node}:/tmp/
		rm -rf /tmp/runsql_server_$node.log
	fi

	# Saving all nodes db list to a file on execution_node
	echo "'$last_node_sid $db_list'" | ssh $execution_node -q 'cat > /tmp/last_node_sid_values.txt'
	echo "'$last_node_db_names'" | ssh $execution_node -q 'cat > /tmp/last_node_db_names.txt'

#End of script
