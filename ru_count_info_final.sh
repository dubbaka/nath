#!/usr/bin/env bash

#Author: Ranganath Reddy Dubbaka
#Date: 25-July-2023

# Set Profile Environment.
. /home/oracle/.bash_profile

#functions to get SQL statement results
function get_db_sql_result() {
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

function get_pdb_sql_result() {
sql_result=$($ORACLE_HOME/bin/sqlplus -S /nolog << EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
set echo off
set feedback off
set heading off
set pages 0
alter session set container = $2;
$1;
exit;
EOF
)
echo "$sql_result"
}

function exec_sql_for_mount(){
$ORACLE_HOME/bin/sqlplus -S /nolog <<EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
SET FEEDBACK OFF;
SET HEAD OFF;
SET PAGESIZE 0;
SET COLSEP ',';
SET MARKUP CSV ON;
SET LINESIZE 1000;
SPOOL db_info.csv
select
'DB03' as SHORTCODE,
'Database' as CATEGORY,
'Oracle ExaCC' as SUB_CATEGORY,
'$cluster_name' as CLUSTER_NAME,
nvl('$db_nodes','$server') as DB_NODES,
'$db' as CDB_NAME,
'' as PDB_NAME,
'$env' as ENVIRONMENT,
'$remarks' as REMARKS,
'' as INT_COUNT,
'' as VERSION
from dual;
SPOOL OFF
exit;
EOF
cat db_info.csv >> /tmp/ru_count_info_$server.csv
}

function exec_sql_for_pdb(){
$ORACLE_HOME/bin/sqlplus -S /nolog <<EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
SET FEEDBACK OFF;
SET HEAD OFF;
SET PAGESIZE 0;
SET COLSEP ',';
SET MARKUP CSV ON;
SET LINESIZE 1000;
alter session set container = $1;
SPOOL db_info.csv
select
'DB03' as SHORTCODE,
'Database' as CATEGORY,
'Oracle ExaCC' as SUB_CATEGORY,
'$cluster_name' as CLUSTER_NAME,
nvl('$instance_nodes','$server') as DB_NODES,
(select name from v\$database) as CDB_NAME,
(select name from v\$pdbs) as PDB_NAME,
'$env' as ENVIRONMENT,
'$remarks' as REMARKS,
$instance_count as INT_COUNT,
'$db_version' as VERSION
from dual;
SPOOL OFF
exit;
EOF
cat db_info.csv >> /tmp/ru_count_info_$server.csv
}

function exec_sql_for_db(){
$ORACLE_HOME/bin/sqlplus -S /nolog <<EOF
connect / as sysdba
whenever sqlerror exit sql.sqlcode
SET FEEDBACK OFF;
SET HEAD OFF;
SET PAGESIZE 0;
SET COLSEP ',';
SET MARKUP CSV ON;
SET LINESIZE 1000;
SPOOL db_info.csv
select
'DB03' as SHORTCODE,
'Database' as CATEGORY,
'Oracle ExaCC' as SUB_CATEGORY,
'$cluster_name' as CLUSTER_NAME,
nvl('$instance_nodes','$server') as DB_NODES,
(select name from v\$database) as CDB_NAME,
'NON-CDB' as PDB_NAME,
'$env' as ENVIRONMENT,
'$remarks' as REMARKS,
$instance_count as INT_COUNT,
'$db_version' as VERSION
from dual;
SPOOL OFF
exit;
EOF
cat db_info.csv >> /tmp/ru_count_info_$server.csv
}

cluster_name=$(ps -ef | grep tnslsnr | grep ASM | awk '{ print $8 }' | sed 's/tnslsnr/cemutlo/')
cluster_name=$($cluster_name -n)
host=$(hostname)
server=$(echo $(hostname) | cut -d '.' -f1)

# Removing and re-creating ru_count_info_$server.csv file.
rm -rf /tmp/ru_count_info_$server.csv
touch /tmp/ru_count_info_$server.csv

# Get sid value from the environment, after validation just saving database names into it.
db_list=$(ps -ef | grep pmon | grep -v grep | grep -v + | awk '{ print $8 }' | cut -d '_' -f3 | sed 's/[0-9]$//')

if [[ -z $db_list ]]; then
	echo "--------------------------------------------------------------------------------------------------------------------------------------------------------"
	echo "No database found on node: $server"
fi

# SQL statements that are needed to get required values
open_mode_sql="select open_mode from v\$database"
db_version_sql="select version from v\$instance"
db19_version_sql="select version_full from v\$instance"
db_name_sql="select name from v\$database"
container_sql="select nvl(cdb,'NO') from v\$database"
instance_count_sql="select nvl(count(*),0) from gv\$instance"
instance_nodes_sql1="SELECT distinct SUBSTR(i.HOST_NAME ,1,v.pos-1) as CLUSTER_NODES from gv\$instance i, (SELECT INSTR(HOST_NAME,'.',1,1) as pos from gv\$instance) v order by 1"
instance_nodes_sql2="select HOST_NAME from  gv\$instance"
pdbs_sql="select name from v\$pdbs where name NOT IN ('PDB\$SEED') and  name NOT LIKE '%PDB1'"


# Assiging parameter value after removing single codes.
last_node_sid=$(echo $1 | sed "s/'//g")
execution_node=$2
last_node_db_names=$(echo $3 | sed "s/'//g")

# Set environment respective to server name
non_prod="101 102 103 104 105 106 107 108"
prod="201 202 203 204 205 206 207 208"
dr="301 302 303 304 305 306 307 308"
nodes="ecc301vm01  ecc302vm01 ecc303vm01 ecc304vm01"
env='UNKNOWN'

for check_env in $non_prod
do
        if [[ $server == *"$check_env"* ]]; then
                env="NON-PROD"
        fi
done
for check_env in $nodes
do
        if [[ $server == $check_env ]]; then
                env="NON-PROD"
        fi
done
for check_env in $prod
do
        if [[ $server == *"$check_env"* ]]; then
                env="PROD"
        fi
done
for check_env in $dr
do
        if [[ $server == *"$check_env"* ]]; then
                env="DR"
        fi
done

# Loop all database names that are saved in db_list.
for db in $db_list
do
	echo "--------------------------------------------------------------------------------------------------------------------------------------------------------"
	echo "Checking ( Database:$db Server:$server )"
    
	# Check if the database details are already captured, then this condition is will not allow any duplicates.
    if echo "${last_node_sid[@]}" | grep -qv "$db";
    then
		if [ -f $HOME/$db.env ]; then
			
			# Set database environment.
			source $HOME/$db.env > /dev/null 2>&1
			
			# Get a few required values.
			open_mode=$(get_db_sql_result "${open_mode_sql}")
			db_nodes=$(srvctl config database -d $db | grep nodes | awk '{ print $3 }' | sed 's/,/ /g')
			
			#Check if the database in not opened.
			if [[ "${open_mode[*]} " =~ "ORA-01507" ]]; then
				echo "Database: $db not mounted"
				remarks="ERROR: Database Not Mounted"
				exec_sql_for_mount
			else
				db_version=$(get_db_sql_result "${db_version_sql}")
				db_version=$(echo $db_version | cut -d '.' -f1)
				db_name=$(get_db_sql_result "${db_name_sql}")
				if echo "${last_node_db_names[@]}" | grep -qv "$db_name"; then
					
					# Checking for database version equal to 19.
					if [[ $db_version -ge 12 ]]
					then
						container=$(get_db_sql_result "${container_sql}")
						db_version=$(get_db_sql_result "${db_version_sql}")
						instance_count=$(get_db_sql_result "${instance_count_sql}")
					else
						container='NO'
						db_version=$(get_db_sql_result "${db_version_sql}")
						instance_count=$(get_db_sql_result "${instance_count_sql}")
					fi
					
					instance_nodes=$(get_db_sql_result "${instance_nodes_sql1}")
					
					if [[ -z $instance_nodes ]]; then
						instance_nodes=$(get_db_sql_result "${instance_nodes_sql2}")
					fi
					
					instance_nodes=$(echo $instance_nodes | sed ':a;N;$!ba;s/\n/ /g')
					instance_count=`echo $instance_count | sed 's/ *$//g'`
					
					# Assigning remarks respective to intance_count values
					if [[ $instance_count -eq 1 ]]; then
						remarks='One instance'
					elif [[ $instance_count -eq 2 ]]; then
						remarks='Two instance'
					elif [[ $instance_count -eq 3 ]]; then
						remarks='Three instance'
					elif [[ $instance_count -eq 4 ]]; then
						remarks='Four instance'
					else
						remarks='None'
					fi
					
					# Get major version number which is before first decimal.
					db_version=$(echo $db_version | cut -d '.' -f1)
					
					# Checking for database version equal to 19.
					if [[ $db_version -eq 19 ]]
					then
					
						# Checking if the DB is a container database.
						if [[ $container = "YES" ]]
						then
							pdbs=$(get_db_sql_result "${pdbs_sql}")
							for pdb in $pdbs
							do
								db_version=$(get_pdb_sql_result "${db19_version_sql}" "${pdb}")
								exec_sql_for_pdb "${pdb}"
							done
						else
							db_version=$(get_db_sql_result "${db19_version_sql}")
							exec_sql_for_db
						fi
					else
						if [[ $container = "YES" ]]
						then
							pdbs=$(get_db_sql_result "${pdbs_sql}")
							for pdb in $pdbs
							do
								db_version=$(get_pdb_sql_result "${db_version_sql}" "${pdb}")
								exec_sql_for_pdb "${pdb}"
							done
						else
							db_version=$(get_db_sql_result "${db_version_sql}")
							exec_sql_for_db
						fi
					fi
				else
					echo "(Instance Name:$db) or (Environment file:$db.env) not matching with DB_NAME:$db_name) Please check"
					remarks="ERROR: Environment file:$db.env not matching with DB_NAME:$db_name"
					echo "DB03","Database","Oracle ExaCC",""$cluster_name"",""$server"",""$db"","",""$env"",""$remarks"","","" > db_info_not_matched_db_name.csv
					cat db_info_not_matched_db_name.csv
					cat db_info_not_matched_db_name.csv >> /tmp/ru_count_info_$server.csv
				fi
			fi
		else
			echo "Environment file $HOME/$db.env file doesn't exist"
			remarks="ERROR: $db.env file not exist"
			echo "DB03","Database","Oracle ExaCC",""$cluster_name"",""$server"",""$db"","",""$env"",""$remarks"","","" > db_info_no_env.csv
			cat db_info_no_env.csv
			cat db_info_no_env.csv >> /tmp/ru_count_info_$server.csv
		fi
	else
		echo "Database : $db details already Captured, Skipping it" 
	fi
		#appending db_names
		last_node_db_names=$(echo "'$last_node_db_names $db_name'")
		last_node_db_names=$(echo $last_node_db_names | sed "s/'//g")
done

# remove all not required spooled csv files
rm -rf *db_info*.csv

#copy final csv file to node1 /tmp location
if [[ $server != $execution_node ]]; then
	scp -q /tmp/ru_count_info_$server.csv ${execution_node}:/tmp/
	rm -rf /tmp/ru_count_info_$server.csv
fi

# Saving all nodes db list to a file on execution_node
echo "'$last_node_sid $db_list'" | ssh $execution_node -q 'cat > /tmp/last_node_sid_values.txt'
echo "'$last_node_db_names'" | ssh $execution_node -q 'cat > /tmp/last_node_db_names.txt'

#End of Script