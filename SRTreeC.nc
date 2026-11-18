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
	uses interface ParameterInit<uint16_t> as SeedInit;
	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	
	uses interface AMSend as NotifyAMSend;
	uses interface AMPacket as NotifyAMPacket;
	uses interface Packet as NotifyPacket;

	uses interface AMSend as MyMSG_AMSend;
	uses interface AMPacket as MyMSG_AMPacket;
	uses interface Packet as MyMSG_Packet;

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
	uses interface Timer<TMilli> as EpochTimer;
	uses interface Timer<TMilli> as TagTransmitTimer;
	
	uses interface Receive as RoutingReceive;
	uses interface Receive as NotifyReceive;
	uses interface Receive as MyMSG_Receive;
	uses interface Receive as SerialReceive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	uses interface PacketQueue as NotifySendQueue;
	uses interface PacketQueue as NotifyReceiveQueue;

	uses interface PacketQueue as MyMSGSendQueue;
	uses interface PacketQueue as MyMSGReceiveQueue;
}
implementation
{
	uint16_t  roundCounter;
	uint8_t currentQueryType = 0;
	uint8_t currentEpochDuration = 0;
	uint16_t currentMeasurement = 0;
	uint16_t aggSum = 0;
	uint8_t  aggMax = 0;
	uint16_t aggAvgSum = 0;
	uint8_t  aggAvgCount = 0;
	uint16_t aggVarSum = 0;
	uint32_t aggVarSumSq = 0;
	uint8_t  aggVarCount = 0;
	bool isFirstEpoch = TRUE;
	uint8_t currentEpochTag = 0;

	message_t radioMyMSGSendPkt;
	message_t radioRoutingSendPkt;
	message_t radioNotifySendPkt;
	
	#define MAX_ESTIMATED_DEPTH 6
	
	message_t serialPkt;
	//message_t serialRecPkt;
	
	bool RoutingSendBusy=FALSE;
	bool NotifySendBusy=FALSE;
	bool RoutingReceiveBusy=FALSE;
	
#ifdef SERIAL_EN
	bool serialBusy=FALSE;
#endif
	
	bool lostRoutingSendTask=FALSE;
	bool lostNotifySendTask=FALSE;
	bool lostRoutingRecTask=FALSE;
	bool lostNotifyRecTask=FALSE;
	
	uint8_t curdepth;
	uint16_t parentID;
	
	task void sendRoutingTask();
	task void sendNotifyTask();
	task void receiveRoutingTask();
	task void receiveNotifyTask();
	
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
		sim_time_t delay = sim_time() % 1024;
		call SeedInit.init(delay);

		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		setNotifySendBusy(FALSE);
#ifdef SERIAL_EN
		setSerialBusy(FALSE);
#endif
		roundCounter =0;
		
		if(TOS_NODE_ID==0)
		{
#ifdef SERIAL_EN
			call SerialControl.start();
#endif
			curdepth=0;
			parentID=0;
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

	event void MyMSG_AMSend.sendDone(message_t* msg, error_t err)
	{
		MyMSGSendBusy = FALSE;
		dbg("SRTreeC", "MyMSG package sent status: %s\n", (err == SUCCESS) ? "SUCCESS" : "FAIL");

		if (!call MyMSGSendQueue.empty())
		{
			post sendMyMSGTask();
		}
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
	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		RoutingMsg* mrpkt;

		dbg("SRTreeC", "RoutingMsgTimer fired! radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
#ifdef PRINTFDBG_MODE
		printfflush();
		printf("RoutingMsgTimer fired! radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
		printfflush();
#endif

		// 1. Get the payload pointer FIRST before writing to it
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt == NULL)
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsgTimer.fired(): No valid payload... \n");
			printfflush();
#endif
			return;
		}

		if (TOS_NODE_ID == 0)
		{
			roundCounter += 1;
			currentQueryType = (call Random.rand16() % 4) + 1;
			currentEpochDuration = 30 + 10 * (call Random.rand16() % 8);

			dbg("SRTreeC", "\n #################==================== \n");
			dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");
			dbg("SRTreeC", "Root selected QueryType = %u, EpochDuration = %u s\n", currentQueryType, currentEpochDuration);
		}

		if(call RoutingSendQueue.full())
		{
#ifdef PRINTFDBG_MODE
			printf("RoutingSendQueue is FULL!!! \n");
			printfflush();
#endif
			return;
		}
		
		atomic {
			mrpkt->senderID = TOS_NODE_ID;
			mrpkt->depth = curdepth;
			mrpkt->queryType = currentQueryType;       // Populate from stored variable
			mrpkt->epochDuration = currentEpochDuration; // Populate from stored variable
		}
		
		dbg("SRTreeC" , "Sending RoutingMsg... (Query=%u, Epoch=%u)\n", currentQueryType, currentEpochDuration);

#ifdef PRINTFDBG_MODE
		printf("NodeID= %d : RoutingMsg sending...!!!! \n", TOS_NODE_ID);
		printfflush();
#endif		
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone = call RoutingSendQueue.enqueue(tmp);
		
		if(enqueueDone == SUCCESS)
		{
			if (call RoutingSendQueue.size() == 1)
			{
				post sendRoutingTask();
			}
			dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
		}		
	}
	
	event void EpochTimer.fired()
	{
		uint8_t localMeasurement;

		// Increment epoch tag for stale packet protection
		currentEpochTag++;

		if (isFirstEpoch) {
			// First epoch: generate a completely random measurement between 1 and 100
			localMeasurement = (call Random.rand16() % 100) + 1;
			isFirstEpoch = FALSE;
		} else {
			// Subsequent epochs: apply ±25% drift rule bounded within [1, 100]
			int16_t minVal = (int16_t)currentMeasurement - (int16_t)((uint32_t)currentMeasurement * 25 / 100);
			int16_t maxVal = (int16_t)currentMeasurement + (int16_t)((uint32_t)currentMeasurement * 25 / 100);

			if (minVal < 1) {
				minVal = 1;
			}
			if (maxVal > 100) {
				maxVal = 100;
			}

			// Generate a random value within the valid drifted range inclusive
			localMeasurement = minVal + (call Random.rand16() % (maxVal - minVal + 1));
		}

		uint32_t epochMs = (uint32_t)currentEpochDuration * 1000UL;
		uint32_t offset = call Random.rand16() % 50; // Small random offset to avoid collisions among nodes at the same depth
		uint32_t transmitDelay;

		if (epochMs > ((uint32_t)curdepth * 100UL + offset)) {
			transmitDelay = epochMs - ((uint32_t)curdepth * 100UL) - offset;
		} else {
			transmitDelay = 100; // Fallback safety
		}

		dbg("SRTreeC", "Scheduling TagTransmitTimer: depth=%u, delay=%lu ms\n", curdepth, transmitDelay);
#ifdef PRINTFDBG_MODE
		printf("TagTransmitTimer scheduled for %lu ms\n", transmitDelay);
		printfflush();
#endif
		call TagTransmitTimer.startOneShot(transmitDelay);

		// Save current measurement for the next epoch's drift calculation
		currentMeasurement = localMeasurement;

		dbg("SRTreeC", "EpochTimer fired: EpochTag=%u, Generated Measurement=%u (QueryType=%u)\n", 
			currentEpochTag, localMeasurement, currentQueryType);
#ifdef PRINTFDBG_MODE
		printf("EpochTimer fired: EpochTag=%u, Measurement=%u\n", currentEpochTag, localMeasurement);
		printfflush();
#endif

		// Restart the EpochTimer for the next round using currentEpochDuration (converted to ms)
		if (currentEpochDuration > 0) {
			call EpochTimer.startOneShot((uint32_t)currentEpochDuration * 1000);
		} else {
			// Fallback default duration if uninitialized (e.g., 30 seconds)
			call EpochTimer.startOneShot(30000);
		}
	}

	event void TagTransmitTimer.fired()
	{
    message_t tmp;
    error_t enqueueDone;
    void* payload;
    uint8_t payloadLen = 0;

    dbg("SRTreeC", "TagTransmitTimer fired! NodeID=%u at depth=%u preparing to send data (Query=%u).\n", TOS_NODE_ID, curdepth, currentQueryType);
#ifdef PRINTFDBG_MODE
    printf("NodeID=%u TagTransmitTimer fired! Query=%u\n", TOS_NODE_ID, currentQueryType);
    printfflush();
#endif

    // If node is root (depth 0), it doesn't send up to a parent via radio; it can print or handle results.
    if (TOS_NODE_ID == 0)
    {
        dbg("SRTreeC", "Root node reached transmission time. Results for this epoch:\n");
        // Print or handle root aggregation results here
        return;
    }

    if (parentID == 0 || parentID >= 65535)
    {
        dbg("SRTreeC", "TagTransmitTimer: No valid parent to transmit to yet.\n");
        return;
    }

    // Get payload pointer for unified MyMSG packet
    payload = call MyMSG_Packet.getPayload(&tmp, sizeof(VarMsg)); // allocate max possible size temporarily
    if (payload == NULL)
    {
        return;
    }

    // Pack data based on currentQueryType and include local measurement + accumulated values
    switch (currentQueryType)
    {
        case 1: // SUM
        {
            SumMsg* msg = (SumMsg*)payload;
            // Aggregate local measurement with children's aggSum
            msg->sum = (uint16_t)currentMeasurement + aggSum;
            payloadLen = sizeof(SumMsg); // len == 2
            break;
        }
        case 2: // AVG
        {
            AvgMsg* msg = (AvgMsg*)payload;
            msg->sum = (uint16_t)currentMeasurement + aggAvgSum;
            msg->count = 1 + aggAvgCount;
            payloadLen = sizeof(AvgMsg); // len == 3
            break;
        }
        case 3: // VAR (Variance)
        {
            VarMsg* msg = (VarMsg*)payload;
            msg->sum = (uint16_t)currentMeasurement + aggVarSum;
            // Assuming simplified local sumSq for local measurement (e.g., measurement * measurement)
            msg->sumSq = ((uint32_t)currentMeasurement * (uint32_t)currentMeasurement) + aggVarSumSq;
            msg->count = 1 + aggVarCount;
            payloadLen = sizeof(VarMsg); // len == 7
            break;
        }
        case 4: // MAX
        {
            MaxMsg* msg = (MaxMsg*)payload;
            uint8_t localMax = (currentMeasurement > aggMax) ? currentMeasurement : aggMax;
            msg->sum = localMax;
            payloadLen = sizeof(MaxMsg); // len == 1
            break;
        }
        default:
            dbg("SRTreeC", "Invalid query type during transmission: %u\n", currentQueryType);
            return;
    }

    if (call MyMSGSendQueue.full())
    {
        dbg("SRTreeC", "MyMSGSendQueue is FULL! Dropping transmission packet.\n");
        return;
    }

    call MyMSG_AMPacket.setDestination(&tmp, parentID);
    call MyMSG_Packet.setPayloadLength(&tmp, payloadLen);

    enqueueDone = call MyMSGSendQueue.enqueue(tmp);
    if (enqueueDone == SUCCESS)
    {
        dbg("SRTreeC", "Data message successfully enqueued for parent ID=%u (len=%u)\n", parentID, payloadLen);
        if (call MyMSGSendQueue.size() == 1)
        {
            post sendMyMSGTask(); // Make sure you implement sendMyMSGTask() similar to sendRoutingTask()
        }
    }
    else
    {
        dbg("SRTreeC", "Failed to enqueue data message in MyMSGSendQueue.\n");
    }

    // Reset local accumulators for the next epoch/round
		aggSum = 0;
		aggMax = 0;
		aggAvgSum = 0;
		aggAvgCount = 0;
		aggVarSum = 0;
		aggVarSumSq = 0;
		aggVarCount = 0;
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

	event message_t* MyMSG_Receive.receive(message_t* msg, void* payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;

		dbg("SRTreeC", "### MyMSG_Receive.receive() start ##### len=%u\n", len);

		atomic {
			memcpy(&tmp, msg, sizeof(message_t));
		}

		enqueueDone = call MyMSGReceiveQueue.enqueue(tmp);

		if (enqueueDone == SUCCESS)
		{
			post receiveDataTask();
		}
		else
		{
			dbg("SRTreeC", "MyMSGReceiveQueue enqueue failed!\n");
		}

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

	task void receiveDataTask()
	{
    message_t tmp;
    uint8_t len;
    message_t radioDataRecPkt;

    if (call MyMSGReceiveQueue.empty()) {
        return;
    }

    radioDataRecPkt = call MyMSGReceiveQueue.dequeue(); 
    // Depending on your queue implementation, assuming standard dequeue:
    // radioDataRecPkt = call MyMSGReceiveQueue.dequeue();
    
    len = call MyMSG_Packet.payloadLength(&radioDataRecPkt);
    void* payload = call MyMSG_Packet.getPayload(&radioDataRecPkt, len);

    if (payload == NULL) return;

    // Dynamic Payload Sizing aggregation based on incoming len
    switch (len) {
        case sizeof(MaxMsg): { // len == 1
            MaxMsg* msg = (MaxMsg*)payload;
            if (msg->sum > aggMax) {
                aggMax = msg->sum;
            }
            break;
        }
        case sizeof(SumMsg): { // len == 2
            SumMsg* msg = (SumMsg*)payload;
            aggSum += msg->sum;
            break;
        }
        case sizeof(AvgMsg): { // len == 3
            AvgMsg* msg = (AvgMsg*)payload;
            aggAvgSum += msg->sum;
            aggAvgCount += msg->count;
            break;
        }
        case sizeof(VarMsg): { // len == 7
            VarMsg* msg = (VarMsg*)payload;
            aggVarSum += msg->sum;
            aggVarSumSq += msg->sumSq;
            aggVarCount += msg->count;
            break;
        }
        default:
            dbg("SRTreeC", "Unknown data packet length received: %u\n", len);
            break;
    }

    dbg("SRTreeC", "Aggregated data packet of len=%u successfully.\n", len);
#ifdef PRINTFDBG_MODE
    printf("Aggregated data packet len=%u\n", len);
    printfflush();
#endif
	}

	task void sendMyMSGTask()
	{
    	uint8_t mlen;
    	uint16_t mdest;
    	error_t sendDone;

		if (call MyMSGSendQueue.empty())
		{
			return;
		}

		if (MyMSGSendBusy)
		{
			return;
		}

		radioMyMSGSendPkt = call MyMSGSendQueue.dequeue();
		mlen = call MyMSG_Packet.payloadLength(&radioMyMSGSendPkt);
		mdest = call MyMSG_AMPacket.destination(&radioMyMSGSendPkt);

		sendDone = call MyMSG_AMSend.send(mdest, &radioMyMSGSendPkt, mlen);
		if (sendDone == SUCCESS)
		{
			MyMSGSendBusy = TRUE;
			dbg("SRTreeC", "sendMyMSGTask(): Send returned success (dest=%u, len=%u)\n", mdest, mlen);
		}
		else
		{
			dbg("SRTreeC", "sendMyMSGTask(): Send failed.\n");
		}
	}



	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */
	
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
			
dbg("SRTreeC" , "receiveRoutingTask(): senderID= %d , depth= %d , query=%u, epoch=%u\n", mpkt->senderID , mpkt->depth, mpkt->queryType, mpkt->epochDuration);
#ifdef PRINTFDBG_MODE
			printf("NodeID= %d , RoutingMsg received from %u! \n", TOS_NODE_ID, mpkt->senderID);
			printfflush();
#endif
			if ( (parentID < 0) || (parentID >= 65535) )
			{
				// First time joining the tree: set parent, depth, query, and epoch
				parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
				curdepth = mpkt->depth + 1;
				currentQueryType = mpkt->queryType;         // Set once upon joining
				currentEpochDuration = mpkt->epochDuration;

				{
				uint32_t epochMs = (uint32_t)currentEpochDuration * 1000UL;
				uint32_t slotMs = epochMs / (6 + 1); // 6 is MAX_ESTIMATED_DEPTH
				uint8_t effectiveDepth = (curdepth < 6) ? curdepth : (6 - 1);
				uint32_t startDelay = (6 - effectiveDepth) * slotMs;
				
				call EpochTimer.startOneShot(startDelay);
				}


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
	
}