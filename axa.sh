#!/bin/bash

############################################################################
#
# script to check status, start and stop both all AXA services or to restart individual components
# supports options: start | stop | status | Aggregator | Apache-tomee | Apache-tomcat | DxC | Logstash | Kafka | Elasticsearch
# kopja02, @ CA 2017. Tested with CA AXA 16.4, and 16.41
#
###########################################################################


SCRIPT_NAME=${BASH_SOURCE##*/}


# Get standard environment variables

export USER_INSTALL_DIR=/opt/CA/axa
export SFTWR_DIR=/opt/CA/software
export AXA_BUILD_DIR=/opt/CA/installs/AXA
export CA_EMM_HOME=$USER_INSTALL_DIR

export AXC_HOSTNAME=localhost
export SERVER_HOSTNAME=localhost
export FRONTEND_HOSTNAME=localhost
export KAFKA_HOSTNAME=localhost
export ZOOKEEPER_HOSTNAME=localhost
export TOMEE_FOLDER_NAME=apache-tomee-plus-1.7.1
export LOGSTASH_FOLDER_NAME=logstash-2.3.4
export AXA_INSTALL_SCRIPTS_DIR=$AXA_BUILD_DIR/bin
export CA_EMM_HOME=$USER_INSTALL_DIR
export SERVER_TOMEE_HOME=$CA_EMM_HOME/$TOMEE_FOLDER_NAME
export FRONTEND_TOMEE_HOME=$CA_EMM_HOME/$TOMEE_FOLDER_NAME
export SERVER_BUILD_DIR=$AXA_BUILD_DIR/server
export AXC_BUILD_DIR=$AXA_BUILD_DIR/AxC
export FRONTEND_BUILD_DIR=$AXA_BUILD_DIR/frontend
export AGGREGATOR_BUILD_DIR=$AXA_BUILD_DIR/aggregator
export RESOURCES_BUILD_DIR=$AXA_BUILD_DIR/resources
export DBSCRIPTS_INSTALL_DIR=$CA_EMM_HOME/resources/dbscripts
export UTIL_JAR_LIBS=$CA_EMM_HOME/java/libs
export WAR_FILES_DIR=$CA_EMM_HOME/java/wars
export BIN_DIR=$CA_EMM_HOME/bin

#Source the common utility functions
. /opt/CA/axa/bin/util.sh

Start() {

LOG $SCRIPT_NAME "----------------- Executing $SCRIPT_NAME ----------------- \n"

LOG $SCRIPT_NAME "Starting Jarvis components\n"
CURR_DIR="$PWD"
cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
echo "-------------------------------------executing $BASH_SOURCE  --------------------------------------------"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   echo "Exiting as user is Non Root user."
  exit 1
fi

source `dirname $0`/constants.txt

cd ${scriptPath}
./startElasticSearchAsRoot.sh
./startKafka.sh
./startTomcat.sh
./startIndexer.sh
./startVerifier.sh
./startJarvisCron.sh
./startJarvis_es_snapshot.sh

echo "-------------------------------------Comming out of  $BASH_SOURCE  --------------------------------------------"
cd $CURR_DIR

LOG $SCRIPT_NAME "----------------- Executing $SCRIPT_NAME ----------------- \n"

CURR_DIR="$PWD"

# tomee

       LOG $SCRIPT_NAME "Starting the Tomee."
      cd $SERVER_TOMEE_HOME
        ./bin/startup.sh
        LOG $SCRIPT_NAME "SUGGESTION: *** Patience Required. You may get a cup of coffee coz this will be taking its own time! ***/n"
        cd $CURR_DIR
        LOG $SCRIPT_NAME "Check the catalina logs. If any errors, it won't be printed here."

sleep 10

        cd $CA_EMM_HOME/AxC/bin
        LOG $SCRIPT_NAME "The collection will begin as we are starting the DXC!"
        ./dxc.sh start
        cd $CURR_DIR

sleep 10

       cd $CA_EMM_HOME/java/mdo-aggregator/bin
        LOG $SCRIPT_NAME "Hold On! The Aggregator is getting up to take away everything from the DXC."
        nohup ./startAgg.sh >> $CA_EMM_HOME/logs/mdoaggregatorscript.out 2>&1 &
        cd $CURR_DIR

sleep 10

LOG $SCRIPT_NAME "Logstash is also starting. Soon I'll stash the data of DXC. Just Wait!"
       
cd $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME
 nohup bin/logstash -f dxc-logstash-jarvis.conf 2>&1 &
# start Logstash with APM agent
        #nohup $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME/bin/logstash -f $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME/dxc-apm-logstash.conf 2>&1 &
 # nohup bin/logstash -f dxc-apm-logstash.conf 2>&1 &


        LOG $SCRIPT_NAME "Log Collector is also starting. Just Wait!"
        cd $CA_EMM_HOME/bin
        ./startLogCollector.sh


        LOG $SCRIPT_NAME "Log Parser is also starting. Just Wait!"
        cd $CA_EMM_HOME/bin
        ./startLogParser.sh




LOG $SCRIPT_NAME "Wait for all the components to startup"
sleep 300

LOG $SCRIPT_NAME "----------------- Execution of $SCRIPT_NAME Finished ----------------- \n"

#### ####### start axa finished ############################

}

Stop() {


echo  $SCRIPT_NAME "----------------- Executing $SCRIPT_NAME ----------------- \n"

# Method to stop the collector

    # Kill DxC process, if running already
    CURR_DIR="$PWD"
    
 # Kill logstash process, if running already
    PID=`ps -ef  | grep DxC  | grep -v grep | awk '{ print $2 }'`
    if [ -z "$PID" ]; then
        echo "Collector DOWN"
else

cd $CA_EMM_HOME/AxC/bin
     #echo "Stopping Collector..."
    ./dxc.sh stop
    cd $CURR_DIR
fi

# Method to stop logStash


    # Kill logstash process, if running already
    PID=`ps -ef  | grep dxc-logstash-jarvis.conf  | grep -v grep | awk '{ print $2 }'`
    if [ -z "$PID" ]; then
        echo "Logstash DOWN"

    else
    echo "Stopping logstash..."
    kill -9 $PID
fi


# Method to stop aggregator
  
    PID=`ps -ef|grep mdo-aggregator |grep -v grep |awk '{print $2}'`
    if [ -z "$PID" ]; then
        echo "Aggregator DOWN"
       
    else
    echo "Stopping Aggregator..."
    kill -9 $PID
fi


# Method to stop Server components


    # stop the tomee process
    # Added the grep for maxConnections to avoid issue in case of multiple tomee services running
    # We were setting maxConnections explicitly under setenv.sh
    PID=`ps -ef | grep apache-tomee-plus-1.7.1 | grep -v grep | awk '{ print $2 }'`
    if [ -z "$PID" ]; then
        echo "Apache tomee DOWN"
	#return 0
    else
    echo "Stopping Apache Tomee..."
    kill -9 $PID
fi

 # Method to stop Jarvis App Server
 
    
     PID=`ps -ef | grep apache-tomcat | grep -v grep | awk '{ print $2 }'`
     if [ -z "$PID" ]; then
         echo "Apache tomcat DOWN"
      else
     echo "Stopping Apache Tomcat..."
    kill -9 $PID
fi

     # Stop elasticsearch
     
          PID=`ps -ef | grep elasticsearch | grep -v grep | awk '{ print $2 }'`
         if [ -z "$PID" ]; then
             echo "Elasticsearch DOWN"
          else
         echo "Stopping Elasticsearch..."
    kill -9 $PID
fi

# Method to stop zookeeper


    # stop the zookeeper process
    PID=`ps -ef | grep zookeeper | grep -v grep | awk '{ print $2 }'`
    if [ -z "$PID" ]; then
        echo "Zookeeper service DOWN"
	else
    echo "Stopping Zookeeper..."
    kill -9 $PID
fi


# Method to stop kafka server
   # stop the kafka server
    PID=`ps -ef | grep kafka | grep server.properties | grep -v grep | awk '{ print $2 }'`
    if [ -z "$PID" ]; then
        echo "Kafka message broker DOWN"
	
    else
    echo "Stopping Kafka..."
    kill -9 $PID
fi


# stop LogParser

   PID=`ps -ef|grep logparser |grep -v grep |awk '{print $2}'`
    if [ -z "$PID" ]; then
        echo "LogParser DOWN"
       
    else
    echo "Stopping LogParser..."
    kill -9 $PID
fi

# stop LogAnalyzer

   PID=`ps -ef|grep logcollector |grep -v grep |awk '{print $2}'`
    if [ -z "$PID" ]; then
        echo "LogCollector DOWN"
       
    else
    echo "Stopping LogCollector..."
    kill -9 $PID
fi

# stop logger Dlog4j

    # Kill Dlog4j  process, if running already
    PID=`ps -ef  | grep Dlog4j  | grep -v grep | awk '{ print $2 }'`
    if [ -z "$PID" ]; then
        echo "Dlog4j DOWN"

    else
    echo "Stopping Dlog4j..."
    kill -9 $PID
fi
 ###


echo "----------------- Execution of AXA stop Finished ----------------- \n"

####### ### finished stop axa ########### 

}

###################################################################
# 
# Check and display the status of all services
#
##################################################################

Status() {
PID=

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
LBLUE='\033[1;36m'
echo '--------------- Status of AXA services ---------------------'
echo


if ps ax | grep -v grep | grep Kafka > /dev/null
then
    echo -e " JARVIS: Kafka message broker ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep Kafka  | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "

    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else
    echo -e " JARVIS: Kafka message broker ${RED}DOWN${NC}"

fi
echo '-----------------------------------------------------------'


if ps ax | grep -v grep | grep zookeeper.properties > /dev/null
then
    echo -e " JARVIS: Elasticsearch manager Zookeeper ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep zookeeper.properties | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "


    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else
    echo -e " JARVIS: Elasticsearch manager Zookeeper ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep apache-tomcat > /dev/null
then
    echo -e " JARVIS: Apache Tomcat ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep apache-tomcat  | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "

    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else
    echo -e " JARVIS: Apache Tomcat ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep Elasticsearch > /dev/null
then
    echo -e " JARVIS: Elasticsearch ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep Elasticsearch  | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "

    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else
    echo -e " JARVIS: Elasticsearch ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep dxc-logstash-jarvis.conf > /dev/null
then
    echo -e " JARVIS: Logstash ${GREEN}RUNNING${NC} using dxc-logstash-jarvis.conf"
    PID=`ps -ef  | grep dxc-logstash-jarvis.conf  | grep -v grep | awk '{ print $2 }'`
   echo " PID :$PID"

else
    echo -e " JARVIS: Logstash ${RED}DOWN${NC}"

fi


if ps ax | grep -v grep | grep dxc-apm-logstash.conf > /dev/null
then
    echo -e " APM: Logstash ${GREEN}RUNNING${NC} using dxc-apm-logstash.conf"
    PID=`ps -ef  | grep dxc-apm-logstash.conf  | grep -v grep | awk '{ print $2 }'`
   echo "PID :$PID"

else
    echo -e " APM: Logstash ${RED}DOWN${NC} or not installed"

fi


echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep indexer > /dev/null
then
    echo -e " JARVIS: Indexer ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep indexer  | grep -v grep | awk '{ print $2 }'`
   echo " PIDS: $PID"
else
    echo -e " JARVIS: Indexer ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'


if ps ax | grep -v grep | grep verifier > /dev/null
then
    echo -e " JARVIS: Verifier ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep verifier  | grep -v grep | awk '{ print $2 }'`
   echo " PIDS: $PID"
else
    echo -e " JARVIS: Verifier ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep apache-tomee > /dev/null
then
    echo -e " AXA: App server Apache-tomee  ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep apache-tomee  | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "

    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else    
echo -e " AXA: App server Apache-tomee ${RED}DOWN${NC}"

fi
echo '-----------------------------------------------------------'



if ps ax | grep -v grep | grep DigitalExperienceCollector  > /dev/null
then
    echo -e " AXA: DxC Collector ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep DigitalExperienceCollector  | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "

    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else
    echo -e " AXA: DxC Collector ${RED}DOWN${NC}"

fi
echo '-----------------------------------------------------------'



if ps ax | grep -v grep | grep mdo-aggregator > /dev/null
then
    echo -e " AXA: Aggregator ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep mdo-aggregator  | grep -v grep | awk '{ print $2 }'`
    echo " PID :$PID "


else
    echo -e " AXA: Aggregator ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'


if ps ax | grep -v grep | grep Dlog4j > /dev/null
then
    echo -e " Logger Dlog4j ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep Dlog4j  | grep -v grep | awk '{ print $2 }'`
   echo " PIDS: $PID"

else
    echo -e " Logger Dlog4j ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep logcollector > /dev/null
then
    echo -e " LA: Log Collector ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep logcollector  | grep -v grep | awk '{ print $2 }'`
    PORT=`netstat -tulpn | grep $PID | grep -o -P '(\:)[0-9]{1,5}'`
    echo " PID :$PID "

    echo -e " ${LBLUE}PORTS LISTENING${NC} "
    echo -e "${LBLUE}$PORT${NC}"


else
    echo -e " LA: Log Collector ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'


if ps ax | grep -v grep | grep logparser > /dev/null
then
    echo -e " LA: Log Parser ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep logparser  | grep -v grep | awk '{ print $2 }'`
 echo " PID :$PID"
else
    echo -e " LA: Log Parser ${RED}DOWN${NC}"

fi

echo '-----------------------------------------------------------'

#if ps ax | grep -v grep | grep pgsql > /dev/null
if ss -l -n |grep PGSQL > /dev/null
then
    echo -e " DB: Postgres ${GREEN}RUNNING${NC}"
 #   PID=`ps -ef  | grep pgsql  | grep -v grep | awk '{ print $2 }'`
# echo " $PID"
#echo `netstat -pl | grep $PID | grep 'PGSQL.[0-9][0-9][0-9][0-9]'`
else
    echo -e " DB: Postgres ${RED}DOWN${NC} or not installed"

fi
echo

if ps ax | grep -v grep | grep oracle > /dev/null
then
    echo -e " DB: Oracle ${GREEN}RUNNING${NC}"
    PID=`ps -ef  | grep $ORACLE_HOME  | grep -v grep | awk '{ print $2 }'`
 echo "PID: $PID"
echo `netstat -pl | grep $PID | grep ':[0-9][0-9][0-9][0-9]'`
else
    echo -e " DB: Oracle ${RED}DOWN${NC} or not installed"

fi
echo '-----------------------------------------------------------'

if ps ax | grep -v grep | grep java > /dev/null
then
    echo " Java processes running. JAVA_HOME: $JAVA_HOME"
else
    echo " No java processes running"

fi

echo
echo '-----------------------------------------------------------'

}


export CURR_DIR="$PWD"

#################################################################
#
# individual process status services
#
################################################################

Aggregator() {
PID=

echo '--------------- Status of mdo-aggregator services ---------------------'
echo 
echo "This service aggregates raw data and saves it into the SQL DB for Admin console"
echo "Aggregator home: $CA_EMM_HOME/java/mdo-aggregator"
echo "Logs: $CA_EMM_HOME/logs/ca-mdo-aggregator-log.txt"
echo

if ps ax | grep -v grep | grep mdo-aggregator > /dev/null
then
    echo "Aggregator service RUNNING"
    PID=`ps -ef  | grep mdo-aggregator | grep -v grep | awk '{ print $2 }'`
    echo " PIDS: "
        echo $PID
else
    echo "mdo-aggregator DOWN"
    echo "-------------------"
fi

read -p "Do you wish to restart Aggregator?" yn

case $yn in
        [Yy]* )
        
            if [ -z $PID ]; then
	        echo '--------------- Starting Aggregator ----------------------'
		
		       cd $CA_EMM_HOME/java/mdo-aggregator/bin

		        nohup ./startAgg.sh >> $CA_EMM_HOME/logs/mdoaggregatorscript.out 2>&1 &
		        cd $CURR_DIR
		  sleep 5
		            PID=`ps -ef  | grep mdo-aggregator| grep -v grep | awk '{ print $2 }'`
		            echo "NEW PIDS: "
        echo $PID
else

echo '--------------- Stopping Aggregator ----------------------'

 # Kill the aggregator process, if is running already
    PID=`ps -ef|grep mdo-aggregator |grep -v grep |awk '{print $2}'`
    echo "Stopping Aggregator..."
    kill -9 $PID

echo '--------------- Starting Aggregator ----------------------'

       cd $CA_EMM_HOME/java/mdo-aggregator/bin
    
        nohup ./startAgg.sh >> $CA_EMM_HOME/logs/mdoaggregatorscript.out 2>&1 &
        cd $CURR_DIR
  sleep 5
            PID=`ps -ef  | grep mdo-aggregator| grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID
fi
;;
                [Nn]* ) exit;;
* ) echo "Please answer (y)es or (n)o.";;
    esac

}


Apache-tomcat() {
PID=
echo '--------------- Status of Jarvis Apache-tomcat services ---------------------'
echo
echo "This tomcat instance hosts Jarvis REST apis for data ingestion and onboarding"
echo "Home: $CA_EMM_HOME/jarvis/apache-tomcat-8.0.30"
echo "Logs: $CA_EMM_HOME/jarvis/apache-tomcat-8.0.30/logs"
echo


if ps ax | grep -v grep | grep apache-tomcat > /dev/null
then
    echo "Jarvis Apache server service RUNNING"
    PID=`ps -ef  | grep apache-tomcat | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
        echo $PID
else
    echo "Jarvis App Server DOWN"
    echo "----------------------"
fi

read -p "Do you wish to restart Jarvis Apache server?" yn

case $yn in
        [Yy]* )
        
     if [ -z $PID ]; then

echo '--------------- Starting Jarvis Apache Server ----------------------'
		
      cd $CA_EMM_HOME/jarvis/apache-tomcat-8.0.30
        ./bin/startup.sh
        cd $CURR_DIR
sleep 15
	PID=`ps -ef  | grep apache-tomcat | grep -v grep | awk '{ print $2 }'`
	echo "NEW PIDS: "
        echo $PID

else

echo '--------------- Stopping Jarvis Apache Server ----------------------'

    # stop the tomcat process
    echo "Stopping Apache Tomcat..."
    kill -9 $PID

echo '--------------- Starting Jarvis Apache Server ----------------------'

      cd $CA_EMM_HOME/jarvis/apache-tomcat-8.0.30
        ./bin/startup.sh
        cd $CURR_DIR
  sleep 15
            PID=`ps -ef  | grep apache-tomcat | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID
fi
         ;;
                [Nn]* ) exit;;
* ) echo "Please answer (y)es or (n)o.";;
    esac

}



Apache-tomee() {
PID=
echo '--------------- Status of Apache-tomee services ---------------------'
echo
echo "This tomee instance hosts AXA user apps"
echo "Home: $CA_EMM_HOME/apache-tomee-plus-1.7.1"
echo "Logs: $CA_EMM_HOME/apache-tomee-plus-1.7.1/logs"
echo


if ps ax | grep -v grep | grep apache-tomee > /dev/null
then
    echo "App server service RUNNING"
    PID=`ps -ef  | grep apache-tomee | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
        echo $PID
else
    echo "App Server DOWN"
    echo "---------------"
fi

read -p "Do you wish to restart App server?" yn

case $yn in
        [Yy]* )
        
     if [ -z $PID ]; then
	        echo '--------------- Starting App Server ----------------------'
		
      cd $SERVER_TOMEE_HOME
        ./bin/startup.sh
        cd $CURR_DIR
sleep 15
	PID=`ps -ef  | grep apache-tomee | grep -v grep | awk '{ print $2 }'`
	echo "NEW PIDS: "
        echo $PID

else

echo '--------------- Stopping App Server ----------------------'

    # stop the tomee process
    echo "Stopping Apache Tomee..."
    kill -9 $PID

echo '--------------- Starting App Server ----------------------'

      cd $SERVER_TOMEE_HOME
        ./bin/startup.sh
        cd $CURR_DIR
  sleep 15
            PID=`ps -ef  | grep apache-tomee | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID
fi
         ;;
                [Nn]* ) exit;;
* ) echo "Please answer (y)es or (n)o.";;
    esac

}

DxC() {

PID=

echo '--------------- Status of DxC services ---------------------'
echo
echo "This is the Digital Experience Collector DxC"
echo "Home: $CA_EMM_HOME/AxC"
echo "Logs: $CA_EMM_HOME/AxC/logs"
echo


if ps ax | grep -v grep | grep DigitalExperienceCollector  > /dev/null
then
    echo "Collector DxC service RUNNING"
    PID=`ps -ef  | grep DigitalExperienceCollector | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
        echo $PID
else
    echo "Collector DxC DOWN"
    echo "------------------"
fi

read -p "Do you wish to restart DxC?" yn

case $yn in
        [Yy]* )
        
        if [ -z $PID ]; then
        
        echo '--------------- Starting DxC ----------------------'
				
	      cd $CA_EMM_HOME/AxC/bin
	        ./dxc.sh start
	        cd $CURR_DIR
	sleep 5
		PID=`ps -ef  | grep DigitalExperienceCollector | grep -v grep | awk '{ print $2 }'`
		echo "NEW PIDS: "
        echo $PID
        
        else

echo '--------------- Stopping DxC ----------------------'

    # Kill DxC process, if running already
    
    cd $CA_EMM_HOME/AxC/bin
    ./dxc.sh stop
    cd $CURR_DIR
sleep 5

echo '--------------- Starting DxC ----------------------'

        cd $CA_EMM_HOME/AxC/bin
        ./dxc.sh start
        cd $CURR_DIR
  sleep 5
            PID=`ps -ef  | grep DigitalExperienceCollector | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID
        
        fi

         ;;
                [Nn]* ) exit;;
* ) echo "Please answer (y)es or (n)o.";;
    esac

}

Kafka() {
PID=
echo '--------------- Status of Kafka services ---------------------'
echo
echo "This is the Apache Kafka message broker"
echo "Home: $CA_EMM_HOME/jarvis/kafka_2.11-0.9.0.0"
echo "Logs: $CA_EMM_HOME/jarvis/kafka_2.11-0.9.0.0/logs"
echo


if ps ax | grep -v grep | grep kafka | grep server.properties > /dev/null
then
    echo "Kafka service RUNNING"
    PID=`ps -ef | grep kafka | grep server.properties |  grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Kafka DOWN"
    echo "----------"
fi

read -p "Do you wish to restart Kafka and Zookeeper?" yn

case $yn in
        [Yy]* )
        
        if [ -z $PID ]; then
        
        echo '--------------- Starting Kafka ----------------------'
		
	cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startKafka.sh
cd $CURR_DIR
sleep 5
		PID=`ps -ef | grep kafka | grep -v grep | awk '{ print $2 }'`
		echo "NEW PIDS: "
        echo $PID

else

echo '--------------- Stopping Kafka & Zookeeper ----------------------'

   # stop the kafka server
    #PID=`ps -ef | grep kafka | grep -v grep | awk '{ print $2 }'`
    #echo "Stopping kafka server..."
    #kill -9 $PID

cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./stopKafka.sh
cd $CURR_DIR
sleep 5

echo '--------------- Starting Zookeeper & Kafka ----------------------'


cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startKafka.sh
cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep kafka | grep -v grep | awk '{ print $2 }'`
	PID2=`ps -ef  | grep zookeeper | grep -v grep | awk '{ print $2 }'`            
	echo "NEW PIDS: "
        echo $PID $PID2
        
        fi

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}

Zookeeper() {
PID=
echo '--------------- Status of Zookeeper services ---------------------'
echo
echo "This is the Apache Kafka cluster manager"
echo "Home: $CA_EMM_HOME/jarvis/kafka_2.11-0.9.0.0"
echo "Logs: $CA_EMM_HOME/jarvis/kafka_2.11-0.9.0.0/logs"
echo


if ps ax | grep -v grep | grep kafka | grep zookeeper > /dev/null
then
    echo "Zookeeper service RUNNING"
    PID=`ps -ef | grep kafka | grep zookeeper |  grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Zookeeper DOWN"
    echo "--------------"
fi

read -p "Do you wish to restart Zookeeper?" yn

case $yn in
        [Yy]* )

        if [ -z $PID ]; then

        echo '--------------- Starting Zookeeper  ----------------------'

#source constants.txt
cd $CA_EMM_HOME/jarvis
cd kafka* 

nohup bin/zookeeper-server-start.sh config/zookeeper.properties &
#./startKafka.sh
cd $CURR_DIR
sleep 5
                PID=`ps -ef | grep kafka | grep zookeeper | grep -v grep | awk '{ print $2 }'`
                echo "NEW PIDS: "
        echo $PID

else

echo '--------------- Stopping Zookeeper ----------------------'

   # stop the zookeeper
    PID=`ps -ef | grep kafka | grep zookeeper |  grep -v grep | awk '{ print $2 }'`
    echo "Stopping zookeeper..."
    kill -9 $PID

echo '--------------- Starting Zookeeper ----------------------'


cd $CA_EMM_HOME/jarvis
cd kafka*

nohup bin/zookeeper-server-start.sh config/zookeeper.properties &
#./startKafka.sh
cd $CURR_DIR
sleep 5
        #    PID=`ps -ef  | grep kafka | grep -v grep | awk '{ print $2 }'`
        PID=`ps -ef  | grep zookeeper | grep -v grep | awk '{ print $2 }'`
        echo "NEW PIDS: "
        echo $PID

        fi

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}

Logstash() {
PID=
echo '--------------- Status of Logstash services ---------------------'
echo
echo "This is the Jarvis Logstash data collection and log parsing engine"
echo "Home: $CA_EMM_HOME/logstash-2.3.4"
#echo "Logs: $CA_EMM_HOME/jarvis/elasticsearch-2.3.3/logs"
echo


if ps ax | grep -v grep | grep dxc-logstash-jarvis.conf > /dev/null
then
    echo "Jarvis Logstash service RUNNING"
    PID=`ps -ef  | grep dxc-logstash-jarvis.conf | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Logstash DOWN"
    echo "-------------"
fi

read -p "Do you wish to restart Jarvis Logstash?" yn

case $yn in
        [Yy]* )
        
        if [ -z $PID ]; then
        
        echo '--------------- Starting Jarvis Logstash ----------------------'
	
	cd $CA_EMM_HOME/logstash-2.3.4
	
	 nohup bin/logstash -f dxc-logstash-jarvis.conf 2>&1 &
	 
	# start Logstash with APM agent - uncomment if integration is installed

	 # nohup $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME/bin/logstash -f $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME/dxc-apm-logstash.conf 2>&1 &
	 # nohup bin/logstash -f dxc-apm-logstash.conf 2>&1 &
	
	cd $CURR_DIR
	sleep 5
	            PID=`ps -ef  | grep dxc-logstash-jarvis.conf | grep -v grep | awk '{ print $2 }'`
	            echo "NEW PIDS: "
        echo $PID
        
        else

echo '--------------- Stopping Logstash ----------------------'

    # Kill logstash process, if running already
    PID=`ps -ef  | grep dxc-logstash-jarvis.conf | grep -v grep | awk '{ print $2 }'`
    kill -9 $PID


echo '--------------- Starting Logstash ----------------------'

cd $CA_EMM_HOME/logstash-2.3.4

 nohup bin/logstash -f dxc-logstash-jarvis.conf 2>&1 &
 
# start Logstash with APM agent
        #nohup $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME/bin/logstash -f $CA_EMM_HOME/$LOGSTASH_FOLDER_NAME/dxc-apm-logstash.conf 2>&1 &
 # nohup bin/logstash -f dxc-apm-logstash.conf 2>&1 &

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep dxc-logstash-jarvis.conf | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID
        
        fi

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}

Elasticsearch() {
PID=
echo '--------------- Status of Elasticsearch services ---------------------'
echo
echo "This is the Jarvis Elasticsearch search engine and data store"
echo "Home: $CA_EMM_HOME/jarvis/elasticsearch-2.3.3"
echo "Logs: $CA_EMM_HOME/jarvis/elasticsearch-2.3.3/logs"
echo


if ps ax | grep -v grep | grep elasticsearch | grep jarvis > /dev/null
then
    echo "Jarvis Elasticsearch service RUNNING"
    PID=`ps -ef  | grep elasticsearch| grep jarvis | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Elasticsearch DOWN"
    echo "------------------"
fi

read -p "Do you wish to restart Jarvis Elasticsearch?" yn

case $yn in
        [Yy]* )



echo '--------------- Restarting Elasticsearch ----------------------'

cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startElasticSearchAsRoot.sh
 

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep elasticsearch | grep jarvis | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}

Verifier() {

echo '--------------- Status of Jarvis Verifier ---------------------'
echo
echo "This is the Jarvis data verifier"
echo "Home: $CA_EMM_HOME/jarvis/verifier/verifier"
echo "Logs: $CA_EMM_HOME/jarvis/verifier/verifier/logs"
echo


if ps ax | grep -v grep | grep verifier | grep jarvis > /dev/null
then
    echo "Jarvis Verifier RUNNING"
    PID=`ps -ef  | grep verifier | grep jarvis | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Jarvis Verifier DOWN"
    echo "--------------------"
fi

read -p "Do you wish to restart Jarvis Verifier?" yn

case $yn in
        [Yy]* )


if [ -z $PID ]; then

echo '--------------- Restarting Jarvis Verifier ----------------------'

cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startVerifier.sh
 

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep verifier | grep jarvis | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID
        
        else 

echo '--------------- Stopping Jarvis verifier ----------------------'

 # Kill the aggregator process, if is running already
    PID=`ps -ef|grep verifier |grep -v grep |awk '{print $2}'`
    kill -9 $PID

echo '--------------- Restarting Jarvis Verifier ----------------------'

cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startVerifier.sh
 
cd $CURR_DIR

sleep 5
            PID=`ps -ef  | grep verifier | grep jarvis | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID

fi
 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}

Indexer() {

echo '--------------- Status of Jarvis Indexer ---------------------'
echo
echo "This is the Jarvis data indexer"
echo "Home: $CA_EMM_HOME/jarvis/indexer/indexer"
echo "Logs: $CA_EMM_HOME/jarvis/indexer/indexer/logs"
echo


if ps ax | grep -v grep | grep indexer | grep jarvis > /dev/null
then
    echo "Jarvis Indexer RUNNING"
    PID=`ps -ef  | grep indexer | grep jarvis | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Jarvis indexer DOWN"
    echo "--------------------"
fi

read -p "Do you wish to restart Jarvis Indexer?" yn

case $yn in
        [Yy]* )

if [ -z $PID ]; then

echo '--------------- Restarting Jarvis Indexer ----------------------'

cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startIndexer.sh

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep indexer | grep jarvis | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID

else
echo '--------------- Stopping Jarvis indexer ----------------------'

 # Kill the indexer process, if is running already
    PID=`ps -ef|grep indexer |grep -v grep |awk '{print $2}'`
    kill -9 $PID

echo '--------------- Starting Jarvis indexer ----------------------'

# start indexer process
cd $AXA_BUILD_DIR/jarvis/jarvisInstaller
source constants.txt
./startIndexer.sh

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep indexer | grep jarvis | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID


fi

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac

}


Logcollector() {
PID=
echo '--------------- Status of AXA Log Collector ---------------------'
echo
echo "This is the Log Analytisc log collector"
echo "Home: $CA_EMM_HOME/logcollector/logstash-2.3.4"
#echo "Logs: $CA_EMM_HOME/logcollector/logstash-2.3.4"
echo


if ps ax | grep -v grep | grep logcollector > /dev/null
then
    echo "Log analytics collector RUNNING"
    PID=`ps -ef  | grep logcollector | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Log Analytics log collector DOWN"
    echo "--------------------------------"
fi

read -p "Do you wish to restart Log analytics collector?" yn

case $yn in
        [Yy]* )



echo '--------------- Restarting Log analytics collector ----------------------'

cd $AXA_BUILD_DIR/bin
./startLogCollector.sh
 

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep logcollector | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}


Logparser() {
PID=
echo '--------------- Status of AXA Log Parser ---------------------'
echo
echo "This is the Log Analytisc log parser"
echo "Home: $CA_EMM_HOME/logparser/logstash-2.3.4"
#echo "Logs: $CA_EMM_HOME/logparser/logstash-2.3.4/logs"
echo


if ps ax | grep -v grep | grep logparser > /dev/null
then
    echo "Log analytics log parser RUNNING"
    PID=`ps -ef  | grep logparser | grep -v grep | awk '{ print $2 }'`
    echo "PIDS: "
    echo $PID
else
    echo "Log Analytics log parser DOWN"
    echo "--------------------------------"
fi

read -p "Do you wish to restart Log analytics parser?" yn

case $yn in
        [Yy]* )



echo '--------------- Restarting Log analytics parser ----------------------'

cd $AXA_BUILD_DIR/bin
./startLogParser.sh
 

cd $CURR_DIR
sleep 5
            PID=`ps -ef  | grep logparser | grep -v grep | awk '{ print $2 }'`
            echo "NEW PIDS: "
        echo $PID

 ;;
        [Nn]* ) exit;;
        * ) echo "Please answer (y)es or (n)o.";;
    esac


}

case $1 in
  Start|Stop|Status|Aggregator|Apache-tomee|Apache-tomcat|DxC|Logstash|Kafka|Zookeeper|Elasticsearch|Verifier|Indexer|Logcollector|Logparser) $1;;
  *) echo "Run as $0 <Start | Stop | Status | Aggregator | Apache-tomee | Apache-tomcat | DxC | Logstash | Kafka | Zookeeper | Elasticsearch | Verifier | Indexer | Logcollector | Logparser>"; exit 1;
esac





