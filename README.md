# Activity Broker
The Activity Broker forwards event notifications in order from an event source to the appropriate subscribers.

<img src="http://cl.ly/image/1a3J0g2B3w1L/Screen%20Shot%202014-07-01%20at%2008.39.40.png">

## Usage

The application was developed and tested using Ruby 2.1.2.
    
Install gems
    
    bundle install
    
Run the application
    
    ruby bin/activity_broker --event_source_port 9090 --subscriber_port 9099

## Concepts

Application Runner

  This is the application starting point. The class takes
  the event source port, subscriber port and an application event
  logger as configuration parameters, bootstraps all the components
  and starts accepting TCP connections from the event source and
  subscribers. Then the runner kicks off the notification processing by
  starting the main IO event loop.
