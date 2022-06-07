require "rails_helper"

RSpec.describe WebhooksController, type: :request do
  before do
    allow(VerifyWebhookSignature).to receive(:call).and_return(true)
  end

  shared_examples "pull_request event handler" do
    let(:payload) do
      from_fixture = json_fixture("pull_request")
      from_fixture["action"] = action
      from_fixture
    end

    let(:action) { "opened" }

    context "when the action is \"opened\"" do
      it "delegates to ReceivePullRequestEvent" do
        expect { subject }.to change(ReceivePullRequestEvent.jobs, :size).by(1)
      end
    end

    context "when the action is not \"opened\"" do
      let(:action) { "labeled" }

      it "does not create a new ReceivePullRequestEvent job" do
        expect { subject }.to_not change(ReceivePullRequestEvent.jobs, :size)
      end
    end

    it "returns 202 Accepted" do
      subject
      expect(response.status).to be(202)
    end
  end

  shared_examples "issue_comment event handler" do
    let(:payload) { json_fixture("issue_comment") }

    it "creates a new ReceiveIssueCommentEvent job" do
      expect { subject }.to change(ReceiveIssueCommentEvent.jobs, :size).by(1)
    end

    it "returns 202 Accepted" do
      subject
      expect(response.status).to be(202)
    end
  end

  describe "POST pull_request" do
    it_behaves_like "pull_request event handler" do
      subject { post "/webhooks/pull_request", params: JSON.dump(payload), headers: {"content-type" => "application/json"} }
    end
  end

  describe "POST issue_comment" do
    it_behaves_like "issue_comment event handler" do
      subject { post "/webhooks/issue_comment", params: JSON.dump(payload), headers: {"content-type" => "application/json"} }
    end
  end

  describe "POST integration" do
    context "when event is pull_request" do
      it_behaves_like "pull_request event handler" do
        subject { post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json", "X-GitHub-Event" => "pull_request"} }
      end
    end

    context "when event is issue_comment" do
      it_behaves_like "issue_comment event handler" do
        subject { post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json", "X-GitHub-Event" => "issue_comment"} }
      end
    end

    context "when event is installation_repositories" do
      let(:payload) { json_fixture("installation_repositories") }
      it "creates a new ReceiveInstallationRepositoriesEvent job" do
        expect { post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json", "X-GitHub-Event" => "installation_repositories"} }.to change(ReceiveInstallationRepositoriesEvent.jobs, :size).by(1)
      end

      it "passes in the array of repositories from the event payload" do
        expect(ReceiveInstallationRepositoriesEvent).to receive(:perform_async).with(payload["repositories_added"], payload["installation"]["id"])
        post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json", "X-GitHub-Event" => "installation_repositories"}
      end
    end

    context "when the event is push" do
      let(:payload) do
        json_fixture("push", ref: ref)
      end

      subject { post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json", "X-GitHub-Event" => "push"} }

      context "when the pushed branch is master" do
        let(:ref) { "refs/heads/master" }
        it "creates a ReceivePushEvent job" do
          expect { subject }.to change(ReceivePushEvent.jobs, :size).by(1)
        end
      end

      context "when the pushed branch is not master" do
        let(:ref) { "refs/heads/some-other-branch" }
        it "does not enqueue a job" do
          expect { subject }.to_not change(ReceivePushEvent.jobs, :size)
        end
      end
    end

    context "when the event is pull_request_review" do
      let(:payload) do
        json_fixture("pull_request_review")
      end

      subject { post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json", "X-GitHub-Event" => "pull_request_review"} }

      it "creates a ReceivePullRequestReviewEvent job" do
        expect { subject }.to change(ReceivePullRequestReviewEvent.jobs, :size).by(1)
      end
    end

    context "when the webhook signature is invalid" do
      before do
        expect(VerifyWebhookSignature).to receive(:call).and_return(false)
      end

      it "returns 403 unauthorized" do
        post "/webhooks/integration"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  context "when the event was generated by the bot user" do
    let(:payload) do
      {
        sender: {id: 1234}
      }
    end

    it "returns 200 OK" do
      post "/webhooks/integration", params: JSON.dump(payload), headers: {"content-type" => "application/json"}
      expect(response).to have_http_status(:ok)
    end
  end
end
