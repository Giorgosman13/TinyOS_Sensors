#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	AM_MYMSG=13,
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3,
	AM_SIMPLEROUTINGTREEMSG=22,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,
	SEND_CHECK_MILLIS=70000,
	TIMER_PERIOD_MILLI=150000,
	TIMER_FAST_PERIOD=200,
	TIMER_LEDS_MILLI=1000,
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t depth;
	nx_uint8_t queryType;      // 1 for sum, 2 for avg, 3 for variance, 4 for max
    nx_uint8_t epochDuration;  // We take the time in seconds and then we convert it inside the node into miliseconds to do calculations
} RoutingMsg;

typedef nx_struct SumMsg{ 
	nx_uint16_t  sum; 
} SumMsg;

typedef nx_struct MaxMsg{ 
	nx_uint8_t  sum;
} MaxMsg;

typedef nx_struct AvgMsg{
	nx_uint16_t sum;
	nx_uint8_t count;
} AvgMsg;

typedef nx_struct VarMsg{
	nx_uint16_t sum;
	nx_uint32_t sumSq;
	nx_uint8_t count;
} VarMsg;


typedef nx_struct NotifyParentMsg
{
	nx_uint16_t senderID;
	nx_uint16_t parentID;
	nx_uint8_t depth;
} NotifyParentMsg;

#endif