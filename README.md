# Activity Broker

The Activity Broker forwards event notifications in order from an event source to the appropriate subscribers.

<img src="http://cl.ly/image/1a3J0g2B3w1L/Screen%20Shot%202014-07-01%20at%2008.39.40.png">

## Usage

The application was developed and tested using Ruby 2.1.2.
    
Install gems
    
    bundle install
    
Run the application
    
    ruby bin/activity_broker --event_source_port 9090 --subscriber_port 9099
    
## Data Flow


    
## Concepts
[**Application Runner:**](https://github.com/oMartell/activity_broker/blob/master/lib/activity_broker/application_runner.rb) 
This is the application starting point. The class takes the event source port, subscriber port and an application event logger as configuration parameters, bootstraps all the components and starts accepting TCP connections from the event source and subscribers. Then the runner kicks off the notification processing by starting the main IO event loop.

## Data Flow

This is a high level simplified picture of how the data flows through the objects of the system when delivering a private message from the Event Source to a Subscriber. This assumes that the application has already started and the event source and subscriber are already connected.

    -> EventLoop#notify_read
        -> MessageStream#read
            -> EventSourceMessageUnpacker#process_message
                -> NotificationOrdering#process_notification
                    -> NotificationTranslator#process_notification
                        -> NotificationRouter#process_private_message_event
                            -> NotificationDelivery#deliver_notification
                                -> MessageStream#write
                                    -> EventLoop#notify_write


## Feature Tests

- [All subscribers are notified of broadcast event](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Subscribers are notified of new followers](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Subscribers are not notified when people stop following them](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [A subscriber no longer receives updates after unfollowing](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Followers are notified of status updates from users they follow](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Subscribers are notified of private messages](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Subscribers receive notifications in order](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)
- [Event notifications are ignored if subscriber is not connected](https://github.com/oMartell/activity_broker/blob/master/spec/integration/activity_broker_spec.rb#L44)




