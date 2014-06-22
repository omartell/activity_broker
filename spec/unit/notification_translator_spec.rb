require 'spec_helper'

module ActivityBroker
  describe NotificationTranslator do
    let!(:notification_listener) { double }
    let!(:notification_translator) { NotificationTranslator.new(notification_listener) }

    it 'translates broadcast events' do
      expect(notification_listener).to receive(:process_broadcast_event)
        .with(EventNotification.new(1, 'B'))

      notification_translator.process_notification(EventNotification.new(1, 'B'))
    end

    it 'translates follow events' do
      expect(notification_listener).to receive(:process_follow_event)
        .with(EventNotification.new(1, 'F'))

      notification_translator.process_notification(EventNotification.new(1, 'F'))
    end

    it 'translates unfollow events' do
      expect(notification_listener).to receive(:process_unfollow_event)
        .with(EventNotification.new(1, 'U'))

      notification_translator.process_notification(EventNotification.new(1, 'U'))
    end

    it 'translates privates messages' do
      expect(notification_listener).to receive(:process_private_message_event)
        .with(EventNotification.new(1, 'P'))

      notification_translator.process_notification(EventNotification.new(1, 'P'))
    end

    it 'translates status updates' do
      expect(notification_listener).to receive(:process_status_update_event)
        .with(EventNotification.new(1, 'S'))

      notification_translator.process_notification(EventNotification.new(1, 'S'))
    end
  end
end
