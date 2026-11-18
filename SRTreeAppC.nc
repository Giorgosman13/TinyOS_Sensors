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
	components new AMSenderC(AM_NOTIFYPARENTMSG) as NotifySenderC;
	components new AMReceiverC(AM_NOTIFYPARENTMSG) as NotifyReceiverC;
	//Added the new message type
	components new AMSenderC(AM_MYMSG) as MyMSGSenderC;
	components new AMReceiverC(AM_MYMSG) as MyMSGReceiverC;
#ifdef SERIAL_EN
	components new SerialAMSenderC(AM_NOTIFYPARENTMSG);
	components new SerialAMReceiverC(AM_NOTIFYPARENTMSG);
#endif
	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	components new PacketQueueC(SENDER_QUEUE_SIZE) as NotifySendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as NotifyReceiveQueueC;
	//Added the queues for the new message type
	components new PacketQueueC(SENDER_QUEUE_SIZE) as MyMSGSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as MyMSGReceiveQueueC;
	
	components MainC, ActiveMessageC, SerialActiveMessageC, LedsC;
	components new TimerMilliC() as Led0TimerC;
	components new TimerMilliC() as Led1TimerC;
	components new TimerMilliC() as Led2TimerC;
	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as LostTaskTimerC;
	components new TimerMilliC() as EpochTimerC;
	components new TimerMilliC() as TagTransmitTimerC;

	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.Random -> RandomC;
	SRTreeC.SeedInit -> RandomC.SeedInit;

	SRTreeC.RadioControl -> ActiveMessageC;
	SRTreeC.Leds-> LedsC;
	
	SRTreeC.Led0Timer-> Led0TimerC;
	SRTreeC.Led1Timer-> Led1TimerC;
	SRTreeC.Led2Timer-> Led2TimerC;
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.LostTaskTimer->LostTaskTimerC;
	SRTreeC.EpochTimer -> EpochTimerC;
	SRTreeC.TagTransmitTimer -> TagTransmitTimerC;
	
	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	
	SRTreeC.NotifyPacket->NotifySenderC.Packet;
	SRTreeC.NotifyAMPacket->NotifySenderC.AMPacket;
	SRTreeC.NotifyAMSend->NotifySenderC.AMSend;
	SRTreeC.NotifyReceive->NotifyReceiverC.Receive;
	
	SRTreeC.MyMSG_Packet->MyMSGSenderC.Packet;
	SRTreeC.MyMSG_AMPacket->MyMSGSenderC.AMPacket;
	SRTreeC.MyMSG_AMSend->MyMSGSenderC.AMSend;
	SRTreeC.MyMSG_Receive->MyMSGReceiverC.Receive;
	
	
#ifdef SERIAL_EN	
	SRTreeC.SerialReceive->SerialAMReceiverC.Receive;
	SRTreeC.SerialAMSend->SerialAMSenderC.AMSend;
	SRTreeC.SerialAMPacket->SerialAMSenderC.AMPacket;
	SRTreeC.SerialPacket->SerialAMSenderC.Packet;
	SRTreeC.SerialControl->SerialActiveMessageC;
#endif
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	SRTreeC.NotifySendQueue->NotifySendQueueC;
	SRTreeC.NotifyReceiveQueue->NotifyReceiveQueueC;
	SRTreeC.MyMSGSendQueue->MyMSGSendQueueC;
	SRTreeC.MyMSGReceiveQueue->MyMSGReceiveQueueC;
	
}