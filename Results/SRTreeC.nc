#include "SimpleRoutingTree.h"
#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif

module SRTreeC
{
	uses interface Boot;
	uses interface Leds;
	uses interface SplitControl as RadioControl;
#ifdef SERIAL_EN
	uses interface SplitControl as SerialControl;
#endif
	
	uses interface Random;
	uses interface ParameterInit<unit16_t> as SeedInt;

	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;

	uses interface AMSend as MyAMSend;
	uses interface AMPacket as MyAMPacket;
	uses interface Packet as MyPacket;

	uses interface AMSend as MaxAMSend;
	uses interface AMPacket as MaxAMPacket;
	uses interface Packet as MaxPacket;


#ifdef SERIAL_EN
	uses interface AMSend as SerialAMSend;
	uses interface AMPacket as SerialAMPacket;
	uses interface Packet as SerialPacket;
#endif
	uses interface Timer<TMilli> as Led0Timer;
	uses interface Timer<TMilli> as Led1Timer;
	uses interface Timer<TMilli> as Led2Timer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as LostTaskTimer;
	uses interface Timer<TMilli> as MyTimer;
	uses interface Timer<TMilli> as MaxTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;
	uses interface Receive as SerialReceive;
	uses interface Receive as MyReceive;
	uses interface Receive as MaxReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;
	uses interface PacketQueue as MySendQueue;
	uses interface PacketQueue as MyReceiveQueue;

	uses interface PacketQueue as MaxSendQueue;
	uses interface PacketQueue as MaxReceiveQueue;
}
implementation
{
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;
	message_t radioMySendPkt;
	message_t radioMaxSendPkt;
	
	
	message_t serialPkt;
	//message_t serialRecPkt;
	
	bool RoutingSendBusy=FALSE;
	bool NotifySendBusy=FALSE;
	bool MySendBusy=FALSE;
	bool MaxSendBusy=FALSE;

#ifdef SERIAL_EN
	bool serialBusy=FALSE;
#endif
	
	bool lostRoutingSendTask=FALSE;
	bool lostNotifySendTask=FALSE;
	bool lostRoutingRecTask=FALSE;
	bool lostNotifyRecTask=FALSE;
	
	uint8_t curdepth;
	uint16_t parentID;
        uint8_t messageType = 1; // 1 = SecondMsg
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void sendMyTask();
	task void sendMaxTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	task void receiveMyTask();
	task void receiveMaxTask();
	
	void setLostRoutingSendTask(bool state)
	{
		atomic{
			lostRoutingSendTask=state;
		}
		if(state==TRUE)
		{
			//call Leds.led2On();
		}
		else 
		{
			//call Leds.led2Off();
		}
	}
	
	void setLostNotifySendTask(bool state)
	{
		atomic{
		lostNotifySendTask=state;
		}
		
		if(state==TRUE)
		{
			//call Leds.led2On();
		}
		else 
		{
			//call Leds.led2Off();
		}
	}
	
	void setLostNotifyRecTask(bool state)
	{
		atomic{
		lostNotifyRecTask=state;
		}
	}
	
	void setLostRoutingRecTask(bool state)
	{
		atomic{
		lostRoutingRecTask=state;
		}
	}
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
		if(state==TRUE)
		{
			call Leds.led0On();
			call Led0Timer.startOneShot(TIMER_LEDS_MILLI);
		}
		else 
		{
			//call Leds.led0Off();
		}
	}
	
	void setMySendBusy(bool state)
	{
		MySendBusy=state;
        }

	void setNotifySendBusy(bool state)
	{
		atomic{
		NotifySendBusy=state;
		}
		dbg("SRTreeC","NotifySendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
#ifdef PRINTFDBG_MODE
		printf("\t\t\t\t\t\tNotifySendBusy = %s\n", (state == TRUE)?"TRUE":"FALSE");
#endif
		
		if(state==TRUE)
		{
			call Leds.led1On();
			call Led1Timer.startOneShot(TIMER_LEDS_MILLI);
		}
		else 
		{
			//call Leds.led1Off();
		}
	}
#ifdef SERIAL_EN
	void setSerialBusy(bool state)
	{
		serialBusy=state;
		if(state==TRUE)
		{
			call Leds.led2On();
			call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		}
		else
		{
			//call Leds.led2Off();
		}
	}
#endif
	event void Boot.booted()
	{	
		sim_time_t delay= sim_time()%10;
		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);
#ifdef SERIAL_EN
		setSerialBusy(FALSE);
#endif
		roundCounter =0;
		dbg("Boot",random seed =%d\n", delay);
		call SeedInit.init(delay);
		if(TOS_NODE_ID==0)
		{
#ifdef SERIAL_EN
			call SerialControl.start();
#endif
			curdepth=0;
			parentID=0;
			epoch = ((call Random.rand16()%8)+3)*10;
			dbg("Boot", "epoch duration = %d\n",epoch);

			messageType = (call Random.rand16() % 4) +1;
			dbg("Boot", "message Type =%d\n", messageType);

			if (messageType==4){
				call MaxTimer.startOneShot(5*1024);
			}
			else {
				call MyTimer.startOneShot(5*1024);
			}
			
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
#ifdef PRINTFDBG_MODE
			printf("Booted NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			printfflush();
#endif
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
#ifdef PRINTFDBG_MODE
			printf("Booted NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			printfflush();
#endif
		}
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");
#ifdef PRINTFDBG_MODE
			printf("Radio initialized successfully!!!\n");
			printfflush();
#endif
			
			//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//call RoutingMsgTimer.startPeriodic(TIMER_PERIOD_MILLI);
			//call LostTaskTimer.startPeriodic(SEND_CHECK_MILLIS);
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
#ifdef PRINTFDBG_MODE
			printf("Radio initialization failed! Retrying...\n");
			printfflush();
#endif
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");
#ifdef PRINTFDBG_MODE
		printf("Radio stopped!\n");
		printfflush();
#endif
	}
	event void SerialControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Serial" , "Serial initialized successfully! \n");
#ifdef PRINTFDBG_MODE
			printf("Serial initialized successfully! \n");
			printfflush();
#endif
			//call RoutingMsgTimer.startPeriodic(TIMER_PERIOD_MILLI);
		}
		else
		{
			dbg("Serial" , "Serial initialization failed! Retrying... \n");
#ifdef PRINTFDBG_MODE
			printf("Serial initialization failed! Retrying... \n");
			printfflush();
#endif
			call SerialControl.start();
		}
	}
	event void SerialControl.stopDone(error_t err)
	{
		dbg("Serial", "Serial stopped! \n");
#ifdef PRINTFDBG_MODE
		printf("Serial stopped! \n");
		printfflush();
#endif
	}
	
	event void LostTaskTimer.fired()
	{
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		if( lostNotifySendTask)
		{
			post sendNotifyTask();
			setLostNotifySendTask(FALSE);
		}
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
		
		if ( lostNotifyRecTask)
		{
			post receiveNotifyTask();
			setLostNotifyRecTask(FALSE);
		}
	}
	
	event void MyTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		SumMsg* sumpkt;
		AvgMsg* avgpkt;
		VarianceMsg* varpkt;
		dbg("Lab1", "MyTimer fired!\n");

		if (TOS_NODE_ID==0) return;
		
		if (call MySendQueue.full())
			return;
	   	
	   	if (messageType == 1) {	
			sumpkt = (SumMsg*) (call MyPacket.getPayload(&tmp, sizeof(SumMsg)));
			if(sumpkt==NULL)
			{
				dbg("Lab1","MyMsgTimer.fired(): No valid payload... \n");
				return;
			}
			atomic{
			sumpkt->sum = total_sum + my value;
			}

			call MyAMPacket.setDestination(&tmp, parentID);
			call MyPacket.setPayloadLength(&tmp, sizeof(SumMsg));
        }
        else if (messageType == 2) {
			avgpkt = (AvgMsg*) (call MyPacket.getPayload(&tmp, sizeof(AvgMsg)));
			if(avgpkt==NULL)
			{
				dbg("Lab1","MyMsgTimer.fired(): No valid payload2... \n");
				return;
			}
			atomic{
			avgpkt->sum = total_sum + my_value;
			avgpkt->count = total_count + 1;
			}

			call MyAMPacket.setDestination(&tmp, parentID);
			call MyPacket.setPayloadLength(&tmp, sizeof(AvgMsg));

        }


        else if (messageType == 3) {
			varpkt = (VarianceMsg*) (call MyPacket.getPayload(&tmp, sizeof(VarianceMsg)));
			if(varpkt==NULL)
			{
				dbg("Lab1","MyMsgTimer.fired(): No valid payload2... \n");
				return;
			}
			atomic{
			varpkt->sum = total_sum + my_value;
			varpkt->sum2 = total_sum2 + (my_value*my_value);
			varpkt->count = total_count + 1;
			}

			call MyAMPacket.setDestination(&tmp, parentID);
			call MyPacket.setPayloadLength(&tmp, sizeof(VarianceMsg));

        }
		
		enqueueDone=call MySendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call MySendQueue.size()==1)
			{
				post sendMyTask();
			}
			
		}
		else
		{
			dbg("SRTreeC","MyMsg failed to be enqueued in SendingQueue!!!");
		}		
    }


    event void MaxTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		MaxMsg* maxpkt;
		dbg("Lab1", "MyTimer fired!\n");

		if (TOS_NODE_ID==0) return;
		
		if (call MySendQueue.full())
			return;
	   	
	   	if (messageType == 4) {	
			maxpkt = (MaxMsg*) (call MyPacket.getPayload(&tmp, sizeof(MaxMsg)));
			if(maxpkt==NULL)
			{
				dbg("Lab1","MyMsgTimer.fired(): No valid payload... \n");
				return;
			}

			if (my_value > total_max){
				total_max = my_value;
			}
			atomic{
			maxpkt->max=total_max;
			}

			call MyAMPacket.setDestination(&tmp, parentID);
			call MyPacket.setPayloadLength(&tmp, sizeof(MaxMsg));
        }
       
		enqueueDone=call MaxSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call MaxSendQueue.size()==1)
			{
				post sendMaxTask();
			}
			
		}
		else
		{
			dbg("SRTreeC","MaxMsg failed to be enqueued in SendingQueue!!!");
		}		
    }

	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
#ifdef PRINTFDBG_MODE
		printfflush();
		printf("RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
		printfflush();
#endif
		if (TOS_NODE_ID==0)
		{
			roundCounter+=1;
			
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");
			
			call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
		}
		
		if(call RoutingSendQueue.full())
		{
#ifdef PRINTFDBG_MODE
			printf("RoutingSendQueue is FULL!!! \n");
			printfflush();
#endif
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsgTimer.fired(): No valid payload... \n");
			printfflush();
#endif
			return;
		}
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		mrpkt->depth = curdepth;
		mrpkt->messageType = messageType;
		mrpkt->epoch=epoch;
		}
		dbg("SRTreeC" , "Sending RoutingMsg... \n");

#ifdef PRINTFDBG_MODE
		printf("NodeID= %d : RoutingMsg sending...!!!! \n", TOS_NODE_ID);
		printfflush();
#endif		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				dbg("SRTreeC", "SendTask() posted!!\n");
#ifdef PRINTFDBG_MODE
				printf("SendTask() posted!!\n");
				printfflush();
#endif
				post sendRoutingTask();
			}
			
			dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsg enqueued successfully in SendingQueue!!!\n");
			printfflush();
#endif
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
#ifdef PRINTFDBG_MODE			
			printf("RoutingMsg failed to be enqueued in SendingQueue!!!\n");
			printfflush();
#endif
		}		
	}
	
	event void Led0Timer.fired()
	{
		call Leds.led0Off();
	}
	event void Led1Timer.fired()
	{
		call Leds.led1Off();
	}
	event void Led2Timer.fired()
	{
		call Leds.led2Off();
	}
	
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		printfflush();
#endif
		
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("Package sent %s \n", (err==SUCCESS)?"True":"False");
		printfflush();
#endif
		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
		//call Leds.led0Off();
	
		
	}
	
	event void NotifyAMSend.sendDone(message_t *msg , error_t err)
	{
		dbg("SRTreeC", "A Notify package sent... %s \n",(err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("A Notify package sent... %s \n",(err==SUCCESS)?"True":"False");
		printfflush();
#endif
		
	
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("Package sent %s \n", (err==SUCCESS)?"True":"False");
		printfflush();
#endif
		setNotifySendBusy(FALSE);
		
		if(!(call NotifySendQueue.empty()))
		{
			post sendNotifyTask();
		}
		//call Leds.led0Off();
		
		
	}
	
	event void MyAMSend.sendDone(message_t *msg , error_t err)
	{
		dbg("Lab1", "A My package sent... %s \n",(err==SUCCESS)?"True":"False");
	
		setMySendBusy(FALSE);
		
		if(!(call MySendQueue.empty()))
		{
			post sendMyTask();
		}
	}


	event void MaxAMSend.sendDone(message_t *msg , error_t err)
	{
		dbg("Lab1", "A Max package sent... %s \n",(err==SUCCESS)?"True":"False");
	
		setMaxSendBusy(FALSE);
		
		if(!(call MaxSendQueue.empty()))
		{
			post sendMaxTask();
		}
	}


	event void SerialAMSend.sendDone(message_t* msg , error_t err)
	{
		if ( &serialPkt == msg)
		{
			dbg("Serial" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
			printf("Package sent %s \n", (err==SUCCESS)?"True":"False");
			printfflush();
#endif
			setSerialBusy(FALSE);
			
			//call Leds.led2Off();
		}
	}
	
	event message_t* MyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		atomic{
		  memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call MyReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveMyTask();
		}
		else
		{
			dbg("SRTreeC","MyMsg enqueue failed!!! \n");
		}
		
		return msg;
	}


	event message_t* MaxReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		atomic{
		  memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call MaxReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveMaxTask();
		}
		else
		{
			dbg("SRTreeC","MaxMsg enqueue failed!!! \n");
		}
		
		return msg;
	}
	
	event message_t* NotifyReceive.receive( message_t* msg , void* payload , uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource = call NotifyAMPacket.source(msg);
		
		dbg("SRTreeC", "### NotifyReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u   %u \n",((NotifyParentMsg*) payload)->senderID, msource);
#ifdef PRINTFDBG_MODE		
		printf("Something Received!!!, len = %u , npm=%u , rm=%u\n",len, sizeof(NotifyParentMsg), sizeof(RoutingMsg));
		printfflush();
#endif

		//if(len!=sizeof(NotifyParentMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
//#ifdef PRINTFDBG_MODE
			//printf("\t\t Unknown message received!!!\n");
			//printfflush();
//#endif
			//return msg;http://courses.ece.tuc.gr/
		//}
		
		//call Leds.led1On();
		//call Led1Timer.startOneShot(TIMER_LEDS_MILLI);
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call NotifyReceiveQueue.enqueue(tmp);
		
		if( enqueueDone== SUCCESS)
		{
#ifdef PRINTFDBG_MODE
			printf("posting receiveNotifyTask()!!!! \n");
			printfflush();
#endif
			post receiveNotifyTask();
		}
		else
		{
			dbg("SRTreeC","NotifyMsg enqueue failed!!! \n");
#ifdef PRINTFDBG_MODE
			printf("NotifyMsg enqueue failed!!! \n");
			printfflush();
#endif			
		}
		
		//call Leds.led1Off();
		dbg("SRTreeC", "### NotifyReceive.receive() end ##### \n");
		return msg;
	}
//	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		//dbg("SRTreeC", "Something received!!!\n");
#ifdef PRINTFDBG_MODE		
		printf("Something Received!!!, len = %u , npm=%u , rm=%u\n",len, sizeof(NotifyParentMsg), sizeof(RoutingMsg));
		printfflush();
#endif
		//call Leds.led1On();
		//call Led1Timer.startOneShot(TIMER_LEDS_MILLI);
		
		//if(len!=sizeof(RoutingMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
//#ifdef PRINTFDBG_MODE
			//printf("\t\t Unknown message received!!!\n");
			//printfflush();
//#endif
			//return msg;
		//}
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
#ifdef PRINTFDBG_MODE
			printf("posting receiveRoutingTask()!!!! \n");
			printfflush();
#endif
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsg enqueue failed!!! \n");
			printfflush();
#endif			
		}
		
		//call Leds.led1Off();
		
		dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}
	
	event message_t* SerialReceive.receive(message_t* msg , void* payload , uint8_t len)
	{
		// when receiving from serial port
		dbg("Serial","Received msg from serial port \n");
#ifdef PRINTFDBG_MODE
		printf("Reveived message from serial port \n");
		printfflush();
#endif
		return msg;
	}
	
	////////////// Tasks implementations //////////////////////////////
	
	
	task void sendRoutingTask()
	{
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		
#ifdef PRINTFDBG_MODE
		printf("SendRoutingTask(): Starting....\n");
		printfflush();
#endif
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
#ifdef PRINTFDBG_MODE		
			printf("sendRoutingTask():Q is empty!\n");
			printfflush();
#endif
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
#ifdef PRINTFDBG_MODE
			printf(	"sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			printfflush();
#endif
			setLostRoutingSendTask(TRUE);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		//call Leds.led2On();
		//call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");
#ifdef PRINTFDBG_MODE
			printf("\t\tsendRoutingTask(): Unknown message!!!!\n");
			printfflush();
#endif
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
#ifdef PRINTFDBG_MODE
			printf("sendRoutingTask(): Send returned success!!!\n");
			printfflush();
#endif
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
#ifdef PRINTFDBG_MODE
			printf("SendRoutingTask(): send failed!!!\n");
#endif
			//setRoutingSendBusy(FALSE);
		}
	}
	/**
	 * dequeues a message and sends it
	 */
	task void sendNotifyTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		NotifyParentMsg* mpayload;
		
		//message_t radioNotifySendPkt;
		
#ifdef PRINTFDBG_MODE
		printf("SendNotifyTask(): going to send one more package.\n");
		printfflush();
#endif
		if (call NotifySendQueue.empty())
		{
			dbg("SRTreeC","sendNotifyTask(): Q is empty!\n");
#ifdef PRINTFDBG_MODE		
			printf("sendNotifyTask():Q is empty!\n");
			printfflush();
#endif
			return;
		}
		
		if(NotifySendBusy==TRUE)
		{
			dbg("SRTreeC","sendNotifyTask(): NotifySendBusy= TRUE!!!\n");
#ifdef PRINTFDBG_MODE
			printf(	"sendTask(): NotifySendBusy= TRUE!!!\n");
			printfflush();
#endif
			setLostNotifySendTask(TRUE);
			return;
		}
		
		radioNotifySendPkt = call NotifySendQueue.dequeue();
		
		//call Leds.led2On();
		//call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		mlen=call NotifyPacket.payloadLength(&radioNotifySendPkt);
		
		mpayload= call NotifyPacket.getPayload(&radioNotifySendPkt,mlen);
		
		if(mlen!= sizeof(NotifyParentMsg))
		{
			dbg("SRTreeC", "\t\t sendNotifyTask(): Unknown message!!\n");
#ifdef PRINTFDBG_MODE
			printf("\t\t sendNotifyTask(): Unknown message!!\n");
			printfflush();
#endif
			return;
		}
		
		dbg("SRTreeC" , " sendNotifyTask(): mlen = %u  senderID= %u \n",mlen,mpayload->senderID);
#ifdef PRINTFDBG_MODE
		printf("\t\t\t\t sendNotifyTask(): mlen=%u\n",mlen);
		printfflush();
#endif
		mdest= call NotifyAMPacket.destination(&radioNotifySendPkt);
		
		
		sendDone=call NotifyAMSend.send(mdest,&radioNotifySendPkt, mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendNotifyTask(): Send returned success!!!\n");
#ifdef PRINTFDBG_MODE
			printf("sendNotifyTask(): Send returned success!!!\n");
			printfflush();
#endif
			setNotifySendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
#ifdef PRINTFDBG_MODE
			printf("SendNotifyTask(): send failed!!!\n");
#endif
			//setNotifySendBusy(FALSE);
		}
	}
	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */
	
	task void sendMyTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		
		if (call MySendQueue.empty())
		{
			return;
		}
		
		if(MySendBusy==TRUE)
		{
			dbg("Lab1","sendMyTask(): MySendBusy= TRUE!!!\n");
			return;
		}
		
		radioMySendPkt = call MySendQueue.dequeue();
		
		mlen=call MyPacket.payloadLength(&radioMySendPkt);
		
		if ((mlen != sizeof(MyMsg)) && (mlen != sizeof(AvgMsg)) && (mlen != sizeof(VarianceMsg)))
		{
			dbg("Lab1", "\t\t sendMyTask(): Unknown message!!\n");
			return;
		}
		
		mdest= call MyAMPacket.destination(&radioMySendPkt);
		
		
		sendDone=call MyAMSend.send(mdest,&radioMySendPkt, mlen);
		
		if ( sendDone == SUCCESS)
		{
			setMySendBusy(TRUE);
		}
		else
		{
			dbg("Lab1","send failed!!!\n");
		}
    }


    task void sendMaxTask()
	{
		uint8_t mlen;//, skip;
		error_t sendDone;
		uint16_t mdest;
		
		if (call MaxSendQueue.empty())
		{
			return;
		}
		
		if(MaxSendBusy==TRUE)
		{
			dbg("Lab1","sendMaxTask(): MaxSendBusy= TRUE!!!\n");
			return;
		}
		
		radioMaxSendPkt = call MaxSendQueue.dequeue();
		
		mlen=call MaxPacket.payloadLength(&radioMaxSendPkt);
		
		if (mlen != sizeof(MaxMsg))
		{
			dbg("Lab1", "\t\t sendMaxTask(): Unknown message!!\n");
			return;
		}
		
		mdest= call MaxAMPacket.destination(&radioMaxSendPkt);
		
		
		sendDone=call MaxAMSend.send(mdest,&radioMaxSendPkt, mlen);
		
		if ( sendDone == SUCCESS)
		{
			setMaxSendBusy(TRUE);
		}
		else
		{
			dbg("Lab1","send failed!!!\n");
		}
    }

	task void receiveRoutingTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		
#ifdef PRINTFDBG_MODE
		printf("ReceiveRoutingTask():received msg...\n");
		printfflush();
#endif
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
#ifdef PRINTFDBG_MODE
		printf("ReceiveRoutingTask(): len=%u!\n",len);
		printfflush();
#endif
		// processing of radioRecPkt
		
		// pos tha xexorizo ta 2 diaforetika minimata???
				
		if(len == sizeof(RoutingMsg))
		{
			NotifyParentMsg* m;
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			//if(TOS_NODE_ID >0)
			//{
				//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//}
			//
			
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
#ifdef PRINTFDBG_MODE
			printf("NodeID= %d , RoutingMsg received! \n",TOS_NODE_ID);
			printf("receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
			printfflush();
#endif
			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				curdepth= mpkt->depth + 1;
#ifdef PRINTFDBG_MODE
				printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
				printfflush();
#endif
				// tha stelnei kai ena minima NotifyParentMsg ston patera
				
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				m->senderID=TOS_NODE_ID;
				m->depth = curdepth;
				m->parentID = parentID;
				dbg("SRTreeC" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);
#ifdef PRINTFDBG_MODE
				printf("NotifyParentMsg NodeID= %d sent!!! \n", TOS_NODE_ID);
				printfflush();
#endif
				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!");
#ifdef PRINTFDBG_MODE
					printf("receiveRoutingTask(): NotifyParentMsg enqueued successfully!!!");
					printfflush();
#endif
					if (call NotifySendQueue.size() == 1)
					{
						post sendNotifyTask();
					}
				}
				if (TOS_NODE_ID!=0)
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
				call MyTimer.startOneShot(5*1024);
				//call MyTimer.startPeriodicAt(-45*1024,60*1024);
			}
			else
			{
				
				if (( curdepth > mpkt->depth +1) || (mpkt->senderID==parentID))
				{
					uint16_t oldparentID = parentID;
					
				
					parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
					curdepth = mpkt->depth + 1;
				
#ifdef PRINTFDBG_MODE
					printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
					printfflush();
#endif					
									
					
					dbg("SRTreeC" , "NotifyParentMsg sending to node= %d... \n", oldparentID);
#ifdef PRINTFDBG_MODE
					printf("NotifyParentMsg sending to node=%d... \n", oldparentID);
					printfflush();
#endif
					if ( (oldparentID<65535) || (oldparentID>0) || (oldparentID==parentID))
					{
						m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
						m->senderID=TOS_NODE_ID;
						m->depth = curdepth;
						m->parentID = parentID;
						
						call NotifyAMPacket.setDestination(&tmp,oldparentID);
						//call NotifyAMPacket.setType(&tmp,AM_NOTIFYPARENTMSG);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
								
						if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
						{
							dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
#ifdef PRINTFDBG_MODE
							printf("receiveRoutingTask(): NotifyParentMsg enqueued successfully!!!");
							printfflush();
#endif
							if (call NotifySendQueue.size() == 1)
							{
								post sendNotifyTask();
							}
						}
					}
					if (TOS_NODE_ID!=0)
					{
						call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
					}
					// tha stelnei kai ena minima NotifyParentMsg 
					// ston kainourio patera kai ston palio patera.
					
					if (oldparentID!=parentID)
					{
						m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
						m->senderID=TOS_NODE_ID;
						m->depth = curdepth;
						m->parentID = parentID;
						dbg("SRTreeC" , "receiveRoutingTask():NotifyParentMsg sending to node= %d... \n", parentID);
#ifdef PRINTFDBG_MODE
						printf("NotifyParentMsg NodeID= %d sent!!! \n", TOS_NODE_ID);
						printfflush();
#endif
						call NotifyAMPacket.setDestination(&tmp, parentID);
						call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
						
						if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
						{
							dbg("SRTreeC", "receiveRoutingTask(): NotifyParentMsg enqueued in SendingQueue successfully!!! \n");
#ifdef PRINTFDBG_MODE					
							printf("receiveRoutingTask(): NotifyParentMsg enqueued successfully!!!");
							printfflush();
#endif
							if (call NotifySendQueue.size() == 1)
							{
								post sendNotifyTask();
							}
						}
					}
				}
				
				
			}
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
#ifdef PRINTFDBG_MODE
			printf("receiveRoutingTask():Empty message!!! \n");
			printfflush();
#endif
			setLostRoutingRecTask(TRUE);
			return;
		}
		
	}


////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////	
	
	 
	task void receiveNotifyTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioNotifyRecPkt;
		
#ifdef PRINTFDBG_MODE
		printf("ReceiveNotifyTask():received msg...\n");
		printfflush();
#endif
		radioNotifyRecPkt= call NotifyReceiveQueue.dequeue();
		
		len= call NotifyPacket.payloadLength(&radioNotifyRecPkt);
		
		dbg("SRTreeC","ReceiveNotifyTask(): len=%u \n",len);
#ifdef PRINTFDBG_MODE
		printf("ReceiveNotifyTask(): len=%u!\n",len);
		printfflush();
#endif
		if(len == sizeof(NotifyParentMsg))
		{
			// an to parentID== TOS_NODE_ID tote
			// tha proothei to minima pros tin riza xoris broadcast
			// kai tha ananeonei ton tyxon pinaka paidion..
			// allios tha diagrafei to paidi apo ton pinaka paidion
			
			NotifyParentMsg* mr = (NotifyParentMsg*) (call NotifyPacket.getPayload(&radioNotifyRecPkt,len));
			
			dbg("SRTreeC" , "NotifyParentMsg received from %d !!! \n", mr->senderID);
#ifdef PRINTFDBG_MODE
			printf("NodeID= %d NotifyParentMsg from senderID = %d!!! \n",TOS_NODE_ID , mr->senderID);
			printfflush();
#endif
			if ( mr->parentID == TOS_NODE_ID)
			{
				// tote prosthiki stin lista ton paidion.
				
			}
			else
			{
				// apla diagrafei ton komvo apo paidi tou..
				
			}
			if ( TOS_NODE_ID==0)
			{
#ifdef SERIAL_EN
				if (!serialBusy)
				{ // mipos mporei na mpei san task?
					NotifyParentMsg * m = (NotifyParentMsg *) (call SerialPacket.getPayload(&serialPkt, sizeof(NotifyParentMsg)));
					m->senderID=mr->senderID;
					m->depth = mr->depth;
					m->parentID = mr->parentID;
					dbg("Serial", "Sending NotifyParentMsg to PC... \n");
#ifdef PRINTFDBG_MODE
					printf("Sending NotifyParentMsg to PC..\n");
					printfflush();
#endif
					if (call SerialAMSend.send(parentID, &serialPkt, sizeof(NotifyParentMsg))==SUCCESS)
					{
						setSerialBusy(TRUE);
					}
				}
#endif
			}
			else
			{
				NotifyParentMsg* m;
				memcpy(&tmp,&radioNotifyRecPkt,sizeof(message_t));
				
				m = (NotifyParentMsg *) (call NotifyPacket.getPayload(&tmp, sizeof(NotifyParentMsg)));
				//m->senderID=mr->senderID;
				//m->depth = mr->depth;
				//m->parentID = mr->parentID;
				
				dbg("SRTreeC" , "Forwarding NotifyParentMsg from senderID= %d  to parentID=%d \n" , m->senderID, parentID);
#ifdef PRINTFDBG_MODE
				printf("NotifyParentMsg NodeID= %d sent!\n", TOS_NODE_ID);
				printfflush();
#endif
				call NotifyAMPacket.setDestination(&tmp, parentID);
				call NotifyPacket.setPayloadLength(&tmp,sizeof(NotifyParentMsg));
				
				if (call NotifySendQueue.enqueue(tmp)==SUCCESS)
				{
					dbg("SRTreeC", "receiveNotifyTask(): NotifyParentMsg enqueued in SendingQueue successfully!!!\n");
					if (call NotifySendQueue.size() == 1)
					{
						post sendNotifyTask();
					}
				}

				
			}
			
		}
		else
		{
			dbg("SRTreeC","receiveNotifyTask():Empty message!!! \n");
#ifdef PRINTFDBG_MODE
			printf("receiveNotifyTask():Empty message!!! \n");
			printfflush();
#endif
			setLostNotifyRecTask(TRUE);
			return;
		}
		
	}
	
	task void receiveMyTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioMyRecPkt;
		
		radioMyRecPkt= call MyReceiveQueue.dequeue();
		
		len = call MyPacket.payloadLength(&radioMyRecPkt);
		
		dbg("Lab1","ReceiveMyTask(): len=%u \n",len);

		if (len == sizeof(SumMsg))
		{
			SumMsg* sum_msg = (SumMsg*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                        dbg("Lab1", "Inside receiveMyTask,sum=%u, sum_msg->sum);
                        // ATHROIZEI AYTA TA NOUMERA ME ALLA THS EPOXHS

		}
        else if (len == sizeof(AvgMsg))
		{
			AvgMsg* avg_msg = (AvgMsg*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                        dbg("Lab1", "Inside receiveMyTask, sum=%u, count=%u\n", avg_msg->sum, avg_msg->count);
                        // ATHROIZEI AYTA TA NOUMERA ME ALLA THS EPOXHS

		}


		else if (len == sizeof(VarianceMsg))
		{
			VarianceMsg* var_msg = (VarianceMsg*) (call MyPacket.getPayload(&radioMyRecPkt,len));
                        dbg("Lab1", "Inside receiveMyTask, sum=%u, count=%u, sum2=%u\n", var_msg->sum, var_msg->count, var_msg->sum2);
                        // ATHROIZEI AYTA TA NOUMERA ME ALLA THS EPOXHS

		}

		else{
			dbg("ProjectPart1", "receiveMyTAsk():Empty Message!!!\n")
		}
	}


	task void receiveMaxTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioMaxRecPkt;
		
		radioMaxRecPkt= call MaxReceiveQueue.dequeue();
		
		len = call MaxPacket.payloadLength(&radioMaxRecPkt);
		
		dbg("Lab1","ReceiveMaxTask(): len=%u \n",len);

		if (len == sizeof(MaxMsg))
		{
			MaxMsg* max_msg = (MaxMsg*) (call MaxPacket.getPayload(&radioMaxRecPkt,len));
                        dbg("Lab1", "Inside receiveMaxTask,max=%u, max_msg->max);
                        // ATHROIZEI AYTA TA NOUMERA ME ALLA THS EPOXHS

		
		}

		else{
			dbg("ProjectPart1", "receiveMyTAsk():Empty Message!!!\n")
		}
	}
	
}
