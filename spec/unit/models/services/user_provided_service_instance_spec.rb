require 'spec_helper'

module VCAP::CloudController
  RSpec.describe VCAP::CloudController::UserProvidedServiceInstance, type: :model do
    let(:service_instance) { VCAP::CloudController::UserProvidedServiceInstance.make }

    it_behaves_like 'a model with an encrypted attribute' do
      def new_model
        VCAP::CloudController::UserProvidedServiceInstance.create(
          name: Sham.name,
          space: FactoryBot.create(:space),
          credentials: value_to_encrypt,
        )
      end

      let(:encrypted_attr) { :credentials }
      let(:attr_salt) { :salt }
    end

    it { is_expected.to have_timestamp_columns }

    describe 'Associations' do
      it { is_expected.to have_associated :space }
      it do
        is_expected.to have_associated :service_bindings, associated_instance: ->(service_instance) {
          app = FactoryBot.create(:app, space: service_instance.space)
          ServiceBinding.make(app: app, service_instance: service_instance, credentials: Sham.service_credentials)
        }
      end
    end

    describe 'Validations' do
      let(:max_tags) { ['a' * 1024, 'b' * 1024] }
      it { is_expected.to validate_presence :name }
      it { is_expected.to validate_presence :space }
      it { is_expected.to strip_whitespace :name }
      it { is_expected.to strip_whitespace :syslog_drain_url }

      it 'should not bind an app and a service instance from different app spaces' do
        service_instance = VCAP::CloudController::UserProvidedServiceInstance.make
        VCAP::CloudController::ProcessModelFactory.make(space: service_instance.space)
        service_binding = VCAP::CloudController::ServiceBinding.make
        expect {
          service_instance.add_service_binding(service_binding)
        }.to raise_error VCAP::CloudController::ServiceInstance::InvalidServiceBinding
      end

      it 'raises an error if the route_service_url is not https' do
        expect {
          VCAP::CloudController::UserProvidedServiceInstance.make(route_service_url: 'http://route.url.com')
        }.
          to raise_error(Sequel::ValidationFailed, 'service_instance route_service_url_not_https')
      end

      it 'raises an error if the route_service_url does not have a valid host' do
        expect {
          VCAP::CloudController::UserProvidedServiceInstance.make(route_service_url: 'https://.com')
        }.
          to raise_error(Sequel::ValidationFailed, 'service_instance route_service_url_invalid')
      end

      it 'raises an error if the route_service_url format is invalid' do
        expect {
          VCAP::CloudController::UserProvidedServiceInstance.make(route_service_url: 'https\\route')
        }.
          to raise_error(Sequel::ValidationFailed, 'service_instance route_service_url_invalid')
      end

      it 'accepts user-provided tags where combined length of all tags is exactly 2048 characters' do
        expect {
          UserProvidedServiceInstance.make tags: max_tags
        }.not_to raise_error
      end

      it 'accepts user-provided tags where combined length of all tags is less than 2048 characters' do
        expect {
          UserProvidedServiceInstance.make tags: max_tags[0..50]
        }.not_to raise_error
      end

      it 'does not accept user-provided tags with combined length of over 2048 characters' do
        expect {
          UserProvidedServiceInstance.make tags: max_tags + ['z']
        }.to raise_error(Sequel::ValidationFailed).with_message('tags too_long')
      end

      it 'does not accept a single user-provided tag of length greater than 2048 characters' do
        expect {
          UserProvidedServiceInstance.make tags: ['a' * 2049]
        }.to raise_error(Sequel::ValidationFailed).with_message('tags too_long')
      end
    end

    describe 'Serialization' do
      it { is_expected.to export_attributes :name, :credentials, :space_guid, :type, :syslog_drain_url, :route_service_url, :tags }
      it { is_expected.to import_attributes :name, :credentials, :space_guid, :syslog_drain_url, :route_service_url, :tags }
    end

    describe '#create' do
      it 'saves with is_gateway_service false' do
        instance = VCAP::CloudController::UserProvidedServiceInstance.create(
          name: 'awesome-service',
          space: FactoryBot.create(:space),
          credentials: { 'foo' => 'bar' },
          route_service_url: 'https://route.url.com'
        )
        expect(instance.refresh.is_gateway_service).to be false
      end

      it 'creates a CREATED service usage event' do
        instance = VCAP::CloudController::UserProvidedServiceInstance.make

        event = ServiceUsageEvent.last
        expect(ServiceUsageEvent.count).to eq(1)
        expect(event.state).to eq(Repositories::ServiceUsageEventRepository::CREATED_EVENT_STATE)
        expect(event).to match_service_instance(instance)
      end

      it 'should create the service instance if the route_service_url is empty' do
        VCAP::CloudController::UserProvidedServiceInstance.make(route_service_url: '')
        expect(ServiceInstance.count).to eq(1)
      end
    end

    describe '#delete' do
      it 'creates a DELETED service usage event' do
        instance = VCAP::CloudController::UserProvidedServiceInstance.make
        instance.destroy

        event = VCAP::CloudController::ServiceUsageEvent.last

        expect(VCAP::CloudController::ServiceUsageEvent.count).to eq(2)
        expect(event.state).to eq(Repositories::ServiceUsageEventRepository::DELETED_EVENT_STATE)
        expect(event).to match_service_instance(instance)
      end
    end

    describe '#tags' do
      let(:instance_tags) { %w(a b c) }
      let(:service_instance) { UserProvidedServiceInstance.make(tags: instance_tags) }

      it 'returns the instance tags' do
        expect(service_instance.tags).to eq instance_tags
      end

      context 'when there are no tags' do
        let(:instance_tags) { nil }
        it 'returns an empty array' do
          expect(service_instance.tags).to eq []
        end
      end
    end

    it 'pretends it can #save_with_new_operation' do
      service_instance.save_with_new_operation({ foo: 'bar' }, { baz: 'bot' })
    end
  end
end
