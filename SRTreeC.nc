#include "SimpleRoutingTree.h"
#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif
#define MAX_CHILDREN 500


module SRTreeC
{
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	uses interface Random;
	uses interface ParameterInit<uint16_t> as SeedInit;
	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;

	uses interface AMSend as MyMSG_AMSend;
	uses interface AMPacket as MyMSG_AMPacket;
	uses interface Packet as MyMSG_Packet;

	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as EpochTimer;

	uses interface Receive as RoutingReceive;
	uses interface Receive as MyMSG_Receive;
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;

	uses interface PacketQueue as MyMSGSendQueue;
	uses interface PacketQueue as MyMSGReceiveQueue;
}
implementation
{
	uint16_t  roundCounter = 0;
	uint8_t currentQueryType = 0;
	uint8_t currentEpochDuration = 0;
	uint8_t currentMeasurement = 0;
	uint8_t previousMeasurement = 0;

	uint8_t localMeasurement = 0;

	uint16_t childrenIDs[MAX_CHILDREN];
	uint16_t childrenSum[MAX_CHILDREN];
	uint32_t childrenSumSquared[MAX_CHILDREN];
	uint8_t childrenNum[MAX_CHILDREN];
	uint8_t childrenMax[MAX_CHILDREN];
	uint8_t lastChild = 0;

	bool isFirstEpoch = TRUE;

	message_t radioMyMSGSendPkt;
	message_t radioRoutingSendPkt;
	
	message_t serialPkt;
	//message_t serialRecPkt;
	
	bool RoutingSendBusy=FALSE;

	bool MySendBusy=FALSE;

	
	uint8_t curdepth;
	int16_t parentID;
	
	task void sendRoutingTask();
	task void receiveRoutingTask();
	task void sendMyMSGTask();
	task void receiveMyTask();

	int8_t findChildId(uint16_t id){
		uint8_t i;

		for (i = 0; i<lastChild; i++){
			if(childrenIDs[i] == id){
				return i;
			}
		}
		if(lastChild == MAX_CHILDREN){
			return -1;
		}

		childrenIDs[lastChild]=id;
		childrenSum[lastChild]=0;
		childrenSumSquared[lastChild]=0;
		childrenNum[lastChild]=0;
		childrenMax[lastChild] =0;

		return lastChild++;
	}	
	
	
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
	}

	void setMySendBusy(bool state)
	{
		MySendBusy=state;
        }

	event void Boot.booted()
	{
		sim_time_t delay = sim_time() % 1024;

		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		roundCounter =0;
		dbg("Boot", "random seed = %d\n", delay);
        		call SeedInit.init(delay);
		
		if(TOS_NODE_ID==0)
		{
			curdepth=0;
			parentID=0;
			currentEpochDuration = ((call Random.rand16() % 8) +3)*10;
			dbg("Boot", "epoch duration = %d\n", currentEpochDuration);
			currentQueryType = (call Random.rand16() % 4) +1; //4 diaforetika eidh mhnymatwn
			dbg("Boot", "message type = %d\n", currentQueryType);
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
		}
	}
	
	event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");
	}

	event void MyMSG_AMSend.sendDone(message_t* msg, error_t err)
	{
		setMySendBusy(FALSE);
		dbg("SRTreeC", "MyMSG package sent status: %s\n", (err == SUCCESS) ? "SUCCESS" : "FAIL");

		if (!call MyMSGSendQueue.empty())
		{
			post sendMyMSGTask();
		}
	}
	
	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		RoutingMsg* mrpkt;

		dbg("SRTreeC", "RoutingMsgTimer fired! radioBusy = %s \n",(RoutingSendBusy)?"True":"False");

		if (TOS_NODE_ID==0)
		{
			roundCounter+=1;
			
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   ROUND   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");
			
			call EpochTimer.startPeriodicAt(0,(uint32_t)currentEpochDuration*1024);
		}
		
		if(call RoutingSendQueue.full())
		{
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		mrpkt->depth = curdepth;
		mrpkt->queryType = currentQueryType;
		mrpkt->epochDuration = currentEpochDuration;
		}
		dbg("SRTreeC" , "Sending RoutingMsg... \n");

		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				dbg("SRTreeC", "SendTask() posted!!\n");

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
		error_t enqueueDone;
		uint8_t minVal, maxVal;

		uint16_t total_sum = 0;
		uint32_t total_sum_squared = 0;
		uint8_t total_count = 0;
		uint8_t total_max = 0;

		float var,avg;

		message_t tmp;
		SumMsg* sumpkt;
		AvgMsg* avgpkt;
		VarMsg* varpkt;
		MaxMsg* maxpkt;

		uint8_t i;
		if(TOS_NODE_ID == 0){
				switch (currentQueryType){
					case 1:
						for(i=0;i<lastChild;i++){
							total_sum += childrenSum[i];
						}
						dbg("Project", "We have reached the root!! Total_sum = %u\n ", total_sum);
						break;
					case 2:
						for(i=0;i<lastChild;i++){
							total_sum += childrenSum[i];
							total_count += childrenNum[i];
						}

						if (total_count == 0)  //den uparxei dendro
						{
							dbg("Project","No children found!!\n ");
							return;
						}

						avg = (float)total_sum/total_count;
						dbg("Project", "Root Message: Total_Average = %f\n ", avg);
						break;

					case 3:
						for(i=0;i<lastChild;i++){
							total_sum += childrenSum[i];
							total_count += childrenNum[i];
							total_sum_squared += childrenSumSquared[i];
						}
						if (total_count == 0)  //den uparxei dendro
						{
							dbg("Project", "No children found!!\n ");
							return;
						}
						avg = (float)total_sum/(float)total_count;
						var = ((float)total_sum_squared/(float)total_count) - (float)(avg * avg);
						dbg("Project","Root Message: Total_Variance = %f\n", var);
						break;
					case 4:
						for(i=0; i<lastChild;i++){
							if(childrenMax[i]>total_max){
								total_max = childrenMax[i];
							}
						}
						dbg("Project", "Root Message: Total_Max = %u\n", total_max);
						break;
					default:
						dbg("Project", "Epoch Timer Fired current query type bugged.\n");
						break;
				}	
			return;
		}

		if (call MyMSGSendQueue.full() ){
			return;
		}

		// 1. Generate measurement (1-100, with +/-25% drift after first epoch)
		if (isFirstEpoch) {
			currentMeasurement = (call Random.rand16() % 100) + 1;
			isFirstEpoch = FALSE;
		} else {
			minVal = currentMeasurement - (currentMeasurement * 0.25);
			maxVal = currentMeasurement + (currentMeasurement * 0.25);
			if (minVal < 1){
				minVal = 1;
			} 
			if (maxVal > 100)
			{
				maxVal = 100;
			} 
			currentMeasurement = minVal + (call Random.rand16() % (maxVal - minVal + 1));
		}

		switch (currentQueryType) {
			case 1: // SUM
				sumpkt = (SumMsg*) (call MyMSG_Packet.getPayload(&tmp, sizeof(SumMsg)));
				if (sumpkt == NULL) return;

				for (i = 0; i < lastChild; i++) {
					total_sum += childrenSum[i];
				}
				atomic {
					sumpkt->sum = total_sum + currentMeasurement;
				}
				call MyMSG_AMPacket.setDestination(&tmp, parentID);
				call MyMSG_Packet.setPayloadLength(&tmp, sizeof(SumMsg));
				break;

			case 2: // AVG
				avgpkt = (AvgMsg*) (call MyMSG_Packet.getPayload(&tmp, sizeof(AvgMsg)));
				if (avgpkt == NULL) return;

				for (i = 0; i < lastChild; i++) {
					total_sum += childrenSum[i];
					total_count += childrenNum[i];
				}
				atomic {
					avgpkt->sum = total_sum + currentMeasurement;
					avgpkt->count = total_count + 1;
				}
				call MyMSG_AMPacket.setDestination(&tmp, parentID);
				call MyMSG_Packet.setPayloadLength(&tmp, sizeof(AvgMsg));
				break;

			case 3: // VARIANCE
				varpkt = (VarMsg*) (call MyMSG_Packet.getPayload(&tmp, sizeof(VarMsg)));
				if (varpkt == NULL) return;

				for (i = 0; i < lastChild; i++) {
					total_sum += childrenSum[i];
					total_sum_squared += childrenSumSquared[i];
					total_count += childrenNum[i];
				}
				atomic {
					varpkt->sum = total_sum + currentMeasurement;
					varpkt->sumSq = total_sum_squared + ((uint32_t)currentMeasurement * (uint32_t)currentMeasurement);
					varpkt->count = total_count + 1;
				}
				call MyMSG_AMPacket.setDestination(&tmp, parentID);
				call MyMSG_Packet.setPayloadLength(&tmp, sizeof(VarMsg));
				break;

			case 4: // MAX
				maxpkt = (MaxMsg*) (call MyMSG_Packet.getPayload(&tmp, sizeof(MaxMsg)));
				if (maxpkt == NULL) return;

				for (i = 0; i < lastChild; i++) {
					if (childrenMax[i] > total_max) {
						total_max = childrenMax[i];
					}
				}
				if (currentMeasurement > total_max) {
					total_max = currentMeasurement;
				}
				atomic {
					maxpkt->sum = total_max; 
				}
				call MyMSG_AMPacket.setDestination(&tmp, parentID);
				call MyMSG_Packet.setPayloadLength(&tmp, sizeof(MaxMsg));
				break;

			default:
				return;
		}
		
		enqueueDone = call MyMSGSendQueue.enqueue(tmp);
		if (enqueueDone == SUCCESS) {
			if (call MyMSGSendQueue.size() == 1) {
				post sendMyMSGTask();
			}
		} else {
			dbg("Project", "Message failed to be enqueued in MyMSGSendQueue!\n");
		}
		
	}
	
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");

		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
	}
	
	
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");	
		}
		
		//call Leds.led1Off();
		
		dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
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
			post receiveMyTask();
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
	
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
		}
	}

	task void receiveMyTask()
	{
		message_t radioDataRecPkt;
		uint8_t len;
		uint16_t sourceID;
		int8_t childIdx;
		void* payload;

		if (call MyMSGReceiveQueue.empty())
		{
			return;
		}

		radioDataRecPkt = call MyMSGReceiveQueue.dequeue();
		sourceID = call MyMSG_AMPacket.source(&radioDataRecPkt);
		len = call MyMSG_Packet.payloadLength(&radioDataRecPkt);
		payload = call MyMSG_Packet.getPayload(&radioDataRecPkt, len);

		if (payload == NULL)
		{
			return;
		}

		childIdx = findChildId(sourceID);
		if (childIdx < 0)
		{
			dbg("SRTreeC", "receiveMyTask(): Child table full or invalid ID for sender %u\n", sourceID);
			return;
		}

		switch (len)
		{
			case sizeof(MaxMsg): // len == 1
			{
				MaxMsg* msg = (MaxMsg*)payload;
				childrenMax[childIdx] = msg->sum;
				break;
			}
			case sizeof(SumMsg): // len == 2
			{
				SumMsg* msg = (SumMsg*)payload;
				childrenSum[childIdx] = msg->sum;
				break;
			}
			case sizeof(AvgMsg): // len == 3
			{
				AvgMsg* msg = (AvgMsg*)payload;
				childrenSum[childIdx] = msg->sum;
				childrenNum[childIdx] = msg->count;
				break;
			}
			case sizeof(VarMsg): // len == 7
			{
				VarMsg* msg = (VarMsg*)payload;
				childrenSum[childIdx] = msg->sum;
				childrenSumSquared[childIdx] = msg->sumSq;
				childrenNum[childIdx] = msg->count;
				break;
			}
			default:
				dbg("SRTreeC", "receiveMyTask(): Unexpected payload len=%u from node %u\n", len, sourceID);
				return;
		}

		dbg("SRTreeC", "receiveMyTask(): Updated child slot %d (node %u) for len=%u\n", childIdx, sourceID, len);
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

		if (MySendBusy)
		{
			return;
		}

		radioMyMSGSendPkt = call MyMSGSendQueue.dequeue();
		mlen = call MyMSG_Packet.payloadLength(&radioMyMSGSendPkt);
		mdest = call MyMSG_AMPacket.destination(&radioMyMSGSendPkt);

		sendDone = call MyMSG_AMSend.send(mdest, &radioMyMSGSendPkt, mlen);
		if (sendDone == SUCCESS)
		{
			setMySendBusy(TRUE);
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
		
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
				
		if(len == sizeof(RoutingMsg))
		{
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
			
			dbg("SRTreeC" , "receiveRoutingTask(): senderID= %d , depth= %d , query=%u, epoch=%u\n", mpkt->senderID , mpkt->depth, mpkt->queryType, mpkt->epochDuration);

			if ( (parentID < 0) || (parentID >= 65535) )
			{
				// First time joining the tree: set parent, depth, query, and epoch
				parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
				curdepth = mpkt->depth + 1;
				currentQueryType = mpkt->queryType;         // Set once upon joining
				currentEpochDuration = mpkt->epochDuration;
				
				call EpochTimer.startPeriodicAt(0-(uint32_t)curdepth*1024, (uint32_t)currentEpochDuration*1024);
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
			return;
		}
		
	}


////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////	
	
	 
	
	
}