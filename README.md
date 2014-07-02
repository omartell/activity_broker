# Activity Broker

[![Build Status](https://travis-ci.org/oMartell/activity_broker.svg?branch=master)](https://travis-ci.org/oMartell/activity_broker)
  
The Activity Broker forwards event notifications in order from an event source to the appropriate subscribers.

<img src="http://cl.ly/image/1a3J0g2B3w1L/Screen%20Shot%202014-07-01%20at%2008.39.40.png">

## Usage

The application was developed and tested using Ruby 2.1.2.

Install gems

    bundle install

Run the application

    ruby bin/activity_broker --event_source_port 9090 --subscriber_port 9099

## Data Flow

This is a high level, simplified picture of how the data flows through the objects of the system when delivering a private message from the Event Source to a Subscriber. This assumes that the application has already started and the event source and subscriber are already connected.

    -> EventLoop#notify_read
    -> MessageStream#read
    -> EventSourceMessageUnpacker#process_message
    -> NotificationOrdering#process_notification
    -> NotificationTranslator#process_notification
    -> NotificationRouter#process_private_message_event
    -> NotificationDelivery#deliver_message_to
    -> MessageStream#write
    -> EventLoop#notify_write

## Components

[**Event Loop**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/event_loop.rb)

The Event Loop is the main control flow construct in the application. Listener objects can register read/write interest on IO objects. The event loop is in charge of notifying the listener objects when their registered IO object is ready to be read from or written to. Internally this class uses ruby's IO select to allow for non-blocking program execution.

[**Application Runner**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/application_runner.rb)

This is the application starting point. The class takes the event source port, subscriber port and an application event logger as configuration parameters, bootstraps all the components and starts accepting TCP connections from the event source and subscribers. Then the runner kicks off the notification processing by starting the main IO event loop.

[**Server**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/server.rb)

This class registers itself with the Event Loop to read from the TCP Server instance. The event loop will then notify when a new connection is ready to be accepted. After the server accepts the connection it will call the listener block with an instance of MessageStream.

[**Message Stream**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/message_stream.rb)

Wrapper class around the TCP socket object for non blocking writes and reads. This class is also responsible for handling message boundaries on both reads and writes. After reading a complete message it tells the message listener to process the message.

[**Event Source Message Unpacker**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/event_source_message_unpacker.rb)

This class is in charge of converting the messages from the message stream into event notifications, which are forwarded to the notification listener.

[**Notification Ordering**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/notification_ordering.rb)

This class enqueues notifications and then forwards them in order to the notification listener. The notifications are ordered by id - the first notification starts with id 1.

[**Notification Translator**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/notification_translator.rb)

The main job of this class is to translate a general notification into a more specific notification that is then passed to the object interested in receiving the specific notification types.

[**Subscriber Message Translator**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/subscriber_message_translator.rb)

This class knows that the only message coming from a subscriber is the subscription message. So, when a message arrives it tells the translated message listener to register the subscriber.

[**Notification Router**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/notification_router.rb)

The notification router is in charge of forwarding the notifications to the appropriate subscribers based on the notification received. It also keeps track of the current subscribers followers and uses an instance of NotificationDelivery to write the messages to the subscribers.

[**Notification Delivery**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/notification_delivery.rb)

This class is in charge of delivering a message to a specific subscriber.

[**Application Event Logger**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/application_event_logger.rb)

The Application Event Logger receives application events forwarded by all the application components and decides if those events should be logged and how they should be logged. This class was used for debugging purposes and integration testing.

##Tests

### [Integration Tests](https://github.com/oMartell/activity_broker/blob/master/spec/integration)
- [All subscribers are notified of broadcast event](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Subscribers are notified of new followers](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L62)
- [Subscribers are not notified when people stop following them](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L92)
- [A subscriber no longer receives updates after unfollowing](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L149)
- [Followers are notified of status updates from users they follow](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L129)
- [Subscribers are notified of private messages](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L114)
- [Subscribers receive notifications in order](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L179)
- [Event notifications are ignored if subscriber is not connected](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L207)

### [Unit Tests](https://github.com/oMartell/activity_broker/blob/master/spec/unit)
