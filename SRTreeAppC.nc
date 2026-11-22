#include "SimpleRoutingTree.h"

//Removed every instance of NotifyMessage and SerialMessage since they are not used in the code.

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

	//Added RandomC so we can have random number generation
	components RandomC;

	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;

	//Added a sender and a receiver for the new message
	components new AMSenderC(AM_MYMSG) as MyMSGSenderC;
	components new AMReceiverC(AM_MYMSG) as MyMSGReceiverC;

	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;

	//Added the send and receive queues for the new message
	components new PacketQueueC(SENDER_QUEUE_SIZE) as MyMSGSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as MyMSGReceiveQueueC;
	
	components MainC, ActiveMessageC;

	components new TimerMilliC() as RoutingMsgTimerC;

	//Added a new timer for each message to be aple to split the time into epochs
	components new TimerMilliC() as EpochTimerC;

	//Wiring begins

	SRTreeC.Boot->MainC.Boot;

	//Added	the random number generation and seed setting
	SRTreeC.Random -> RandomC;
	SRTreeC.SeedInit -> RandomC.SeedInit;

	SRTreeC.RadioControl -> ActiveMessageC;
	
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;

	//Added the epoch timer
	SRTreeC.EpochTimer -> EpochTimerC;
	
	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	
	//Creating the packets and creating the sender and receiver
	SRTreeC.MyMSG_Packet->MyMSGSenderC.Packet;
	SRTreeC.MyMSG_AMPacket->MyMSGSenderC.AMPacket;
	SRTreeC.MyMSG_AMSend->MyMSGSenderC.AMSend;
	SRTreeC.MyMSG_Receive->MyMSGReceiverC.Receive;
	
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;

	//Creating the 2 queues for the new message
	SRTreeC.MyMSGSendQueue->MyMSGSendQueueC;
	SRTreeC.MyMSGReceiveQueue->MyMSGReceiveQueueC;
	
}