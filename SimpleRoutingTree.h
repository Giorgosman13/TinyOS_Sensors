#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H


enum{
	//Created new channel ID to seperate the new message type
	AM_MYMSG=13,
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=16,
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

//Added 2 variables in RoutingMsg for the query logic and the time of the epoch
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;		
	nx_uint8_t depth;
	nx_uint8_t queryType;      // 1 for sum, 2 for avg, 3 for variance, 4 for max
    nx_uint8_t epochDuration;  // We take the time in seconds and then we convert it inside the node into miliseconds to do calculations
} RoutingMsg;

//Defining the message types splitting it into the 4 TAGS: Sum, Max, Average and Variance. 
//Since we only created one message ID for our Message type we split them up using their memory size.

//For the sum we only need 2 bytes since the max measurement the node can get is 100 so if the 
//max number it can save is 65,535 then we would need 655 nodes with max value to be children of one node.
//It is a really safe amount of bytes to save
typedef nx_struct SumMsg{ 
	nx_uint16_t  sum; 
} SumMsg; //2 bytes

//For the MAX we just need one byte. That is because the maximum measurement a node can make is 100 which fits in just one byte
typedef nx_struct MaxMsg{ 
	nx_uint8_t  max;
} MaxMsg; //1 byte

//For the average we need 2 different numbers so we can make the calc in the end. We make their sizes as such because
//As we said above the sum is in need of 2 bytes to be safe from overflow and the count can easily fit in 1 byte since
//one node having over 255 children is a really extreme case.
typedef nx_struct AvgMsg{
	nx_uint16_t sum;
	nx_uint8_t count;
} AvgMsg; //3 bytes

//The variance type is: Var = total_sum_squared/Numver of children - avg^2
//So we need to save the sum and count to calculate the average and the sum squared which needs 4 bytes since 
//a value squared is a big value. So for it be safe to run without overflow we need many bytes.
typedef nx_struct VarMsg{
	nx_uint16_t sum;
	nx_uint32_t sumSq;
	nx_uint8_t count;
} VarMsg; //7 bytes

#endif