#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;
	components RandomC;

#if defined(DELUGE) //defined(DELUGE_BASESTATION) || defined(DELUGE_LIGHT_BASESTATION)
	components DelugeC;
#endif

#ifdef PRINTFDBG_MODE
		components PrintfC;
#endif
	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;
	//Added the new message type
	components new AMSenderC(AM_MYMSG) as MyMSGSenderC;
	components new AMReceiverC(AM_MYMSG) as MyMSGReceiverC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;

	//Added the queues for the new message type
	components new PacketQueueC(SENDER_QUEUE_SIZE) as MyMSGSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as MyMSGReceiveQueueC;
	
	components MainC, ActiveMessageC;

	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as EpochTimerC;

	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.Random -> RandomC;
	SRTreeC.SeedInit -> RandomC.SeedInit;

	SRTreeC.RadioControl -> ActiveMessageC;
	
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.EpochTimer -> EpochTimerC;
	
	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	
	SRTreeC.MyMSG_Packet->MyMSGSenderC.Packet;
	SRTreeC.MyMSG_AMPacket->MyMSGSenderC.AMPacket;
	SRTreeC.MyMSG_AMSend->MyMSGSenderC.AMSend;
	SRTreeC.MyMSG_Receive->MyMSGReceiverC.Receive;
	
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;

	SRTreeC.MyMSGSendQueue->MyMSGSendQueueC;
	SRTreeC.MyMSGReceiveQueue->MyMSGReceiveQueueC;
	
}