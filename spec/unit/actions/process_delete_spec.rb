require 'spec_helper'
require 'actions/process_delete'

module VCAP::CloudController
  RSpec.describe ProcessDelete do
    subject(:process_delete) { ProcessDelete.new(user_audit_info) }
    let(:user_audit_info) { instance_double(UserAuditInfo).as_null_object }
    let(:space) { FactoryBot.create(:space) }
    let(:app) { FactoryBot.create(:app, space: space) }

    describe '#delete' do
      context 'when the process exists' do
        let!(:process) { ProcessModel.make(app: app, type: 'potato') }

        it 'deletes the process record' do
          expect {
            process_delete.delete(process)
          }.to change { ProcessModel.count }.by(-1)
          expect(process.exists?).to be_falsey
        end

        it 'creates an audit.app.process.delete event' do
          process_delete.delete(process)

          event = Event.last
          expect(event.type).to eq('audit.app.process.delete')
          expect(event.metadata['process_guid']).to eq(process.guid)
        end

        it 'deletes associated labels' do
          label = ProcessLabelModel.make(resource_guid: process.guid)
          expect {
            process_delete.delete([process])
          }.to change { ProcessLabelModel.count }.by(-1)
          expect(label.exists?).to be_falsey
          expect(process.exists?).to be_falsey
        end

        it 'deletes associated annotations' do
          annotation = ProcessAnnotationModel.make(resource_guid: process.guid)
          expect {
            process_delete.delete([process])
          }.to change { ProcessAnnotationModel.count }.by(-1)
          expect(annotation.exists?).to be_falsey
          expect(process.exists?).to be_falsey
        end
      end

      context 'when deleting multiple' do
        let!(:process1) { ProcessModel.make(:process, app: app) }
        let!(:process2) { ProcessModel.make(:process, app: app) }

        it 'deletes the process record' do
          expect {
            process_delete.delete([process1, process2])
          }.to change { ProcessModel.count }.by(-2)
          expect(process1.exists?).to be_falsey
          expect(process2.exists?).to be_falsey
        end
      end
    end
  end
end
