#!/usr/bin/env rspec
#
#  Created by Luke Kanies on 2007-11-12.
#  Copyright (c) 2007. All rights reserved.

require 'spec_helper'
require 'puppet/configurer'

describe Puppet::Configurer do
  before do
    Puppet.settings.stubs(:use).returns(true)
    @agent = Puppet::Configurer.new
  end

  it "should include the Plugin Handler module" do
    Puppet::Configurer.ancestors.should be_include(Puppet::Configurer::PluginHandler)
  end

  it "should include the Fact Handler module" do
    Puppet::Configurer.ancestors.should be_include(Puppet::Configurer::FactHandler)
  end

  it "should use the puppetdlockfile as its lockfile path" do
    Puppet.settings.expects(:value).with(:puppetdlockfile).returns("/my/lock")
    Puppet::Configurer.lockfile_path.should == "/my/lock"
  end

  describe "when executing a pre-run hook" do
    it "should do nothing if the hook is set to an empty string" do
      Puppet.settings[:prerun_command] = ""
      Puppet::Util.expects(:exec).never

      @agent.execute_prerun_command
    end

    it "should execute any pre-run command provided via the 'prerun_command' setting" do
      Puppet.settings[:prerun_command] = "/my/command"
      Puppet::Util.expects(:execute).with { |args| args[0] == "/my/command" }

      @agent.execute_prerun_command
    end

    it "should fail if the command fails" do
      Puppet.settings[:prerun_command] = "/my/command"
      Puppet::Util.expects(:execute).raises Puppet::ExecutionFailure

      lambda { @agent.execute_prerun_command }.should raise_error(Puppet::Configurer::CommandHookError)
    end
  end

  describe "when executing a post-run hook" do
    it "should do nothing if the hook is set to an empty string" do
      Puppet.settings[:postrun_command] = ""
      Puppet::Util.expects(:exec).never

      @agent.execute_postrun_command
    end

    it "should execute any post-run command provided via the 'postrun_command' setting" do
      Puppet.settings[:postrun_command] = "/my/command"
      Puppet::Util.expects(:execute).with { |args| args[0] == "/my/command" }

      @agent.execute_postrun_command
    end

    it "should fail if the command fails" do
      Puppet.settings[:postrun_command] = "/my/command"
      Puppet::Util.expects(:execute).raises Puppet::ExecutionFailure

      lambda { @agent.execute_postrun_command }.should raise_error(Puppet::Configurer::CommandHookError)
    end
  end
end

describe Puppet::Configurer, "when executing a catalog run" do
  before do
    Puppet.settings.stubs(:use).returns(true)
    @agent = Puppet::Configurer.new
    @agent.stubs(:prepare)
    @agent.stubs(:facts_for_uploading).returns({})
    @catalog = Puppet::Resource::Catalog.new
    @catalog.stubs(:apply)
    @agent.stubs(:retrieve_catalog).returns @catalog
    @agent.stubs(:save_last_run_summary)
    Puppet::Transaction::Report.indirection.stubs(:save)
  end

  it "should prepare for the run" do
    @agent.expects(:prepare)

    @agent.run
  end

  it "should initialize a transaction report if one is not provided" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).at_least_once.returns report

    @agent.run
  end

  it "should pass the new report to the catalog" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.stubs(:new).returns report
    @catalog.expects(:apply).with{|options| options[:report] == report}

    @agent.run
  end

  it "should use the provided report if it was passed one" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).never
    @catalog.expects(:apply).with{|options| options[:report] == report}

    @agent.run(:report => report)
  end

  it "should set the report as a log destination" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns report

    @agent.stubs(:send_report)
    Puppet::Util::Log.expects(:newdestination).with(report)

    @agent.run
  end

  it "should retrieve the catalog" do
    @agent.expects(:retrieve_catalog)

    @agent.run
  end

  it "should log a failure and do nothing if no catalog can be retrieved" do
    @agent.expects(:retrieve_catalog).returns nil

    Puppet.expects(:err).with "Could not retrieve catalog; skipping run"

    @agent.run
  end

  it "should apply the catalog with all options to :run" do
    @agent.expects(:retrieve_catalog).returns @catalog

    @catalog.expects(:apply).with { |args| args[:one] == true }
    @agent.run :one => true
  end

  it "should accept a catalog and use it instead of retrieving a different one" do
    @agent.expects(:retrieve_catalog).never

    @catalog.expects(:apply)
    @agent.run :one => true, :catalog => @catalog
  end

  it "should benchmark how long it takes to apply the catalog" do
    @agent.expects(:benchmark).with(:notice, "Finished catalog run")

    @agent.expects(:retrieve_catalog).returns @catalog

    @catalog.expects(:apply).never # because we're not yielding
    @agent.run
  end

  it "should execute post-run hooks after the run" do
    @agent.expects(:execute_postrun_command)

    @agent.run
  end

  it "should send the report" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns(report)
    @agent.expects(:send_report).with { |r, trans| r == report }

    @agent.run
  end

  it "should send the transaction report with a reference to the transaction if a run was actually made" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns(report)

    trans = stub 'transaction'
    @catalog.expects(:apply).returns trans

    @agent.expects(:send_report).with { |r, t| t == trans }

    @agent.run :catalog => @catalog
  end

  it "should send the transaction report even if the catalog could not be retrieved" do
    @agent.expects(:retrieve_catalog).returns nil

    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns(report)
    @agent.expects(:send_report)

    @agent.run
  end

  it "should send the transaction report even if there is a failure" do
    @agent.expects(:retrieve_catalog).raises "whatever"

    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns(report)
    @agent.expects(:send_report)

    lambda { @agent.run }.should raise_error
  end

  it "should remove the report as a log destination when the run is finished" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns(report)

    report.expects(:<<).at_least_once

    @agent.run
    Puppet::Util::Log.destinations.should_not include(report)
  end

  it "should return the report as the result of the run" do
    report = Puppet::Transaction::Report.new("apply")
    Puppet::Transaction::Report.expects(:new).returns(report)

    @agent.run.should equal(report)
  end
end

describe Puppet::Configurer, "when sending a report" do
  include PuppetSpec::Files

  before do
    Puppet.settings.stubs(:use).returns(true)
    @configurer = Puppet::Configurer.new
    Puppet[:lastrunfile] = tmpfile('last_run_file')

    @report = Puppet::Transaction::Report.new("apply")
    @trans = stub 'transaction'
  end

  it "should finalize the report" do
    @report.expects(:finalize_report)
    @configurer.send_report(@report, @trans)
  end

  it "should print a report summary if configured to do so" do
    Puppet.settings[:summarize] = true

    @report.expects(:summary).returns "stuff"

    @configurer.expects(:puts).with("stuff")
    @configurer.send_report(@report, nil)
  end

  it "should not print a report summary if not configured to do so" do
    Puppet.settings[:summarize] = false

    @configurer.expects(:puts).never
    @configurer.send_report(@report, nil)
  end

  it "should save the report if reporting is enabled" do
    Puppet.settings[:report] = true

    Puppet::Transaction::Report.indirection.expects(:save).with(@report)
    @configurer.send_report(@report, nil)
  end

  it "should not save the report if reporting is disabled" do
    Puppet.settings[:report] = false

    Puppet::Transaction::Report.indirection.expects(:save).never
    @configurer.send_report(@report, nil)
  end

  it "should save the last run summary if reporting is enabled" do
    Puppet.settings[:report] = true

    @configurer.expects(:save_last_run_summary).with(@report)
    @configurer.send_report(@report, nil)
  end

  it "should save the last run summary if reporting is disabled" do
    Puppet.settings[:report] = false

    @configurer.expects(:save_last_run_summary).with(@report)
    @configurer.send_report(@report, nil)
  end

  it "should log but not fail if saving the report fails" do
    Puppet.settings[:report] = true

    Puppet::Transaction::Report.indirection.expects(:save).with(@report).raises "whatever"

    Puppet.expects(:err)
    lambda { @configurer.send_report(@report, nil) }.should_not raise_error
  end
end

describe Puppet::Configurer, "when saving the summary report file" do
  before do
    Puppet.settings.stubs(:use).returns(true)
    @configurer = Puppet::Configurer.new

    @report = stub 'report'
    @trans = stub 'transaction'
    @lastrunfd = stub 'lastrunfd'
    Puppet::Util::FileLocking.stubs(:writelock).yields(@lastrunfd)
  end

  it "should write the raw summary to the lastrunfile setting value" do
    Puppet::Util::FileLocking.expects(:writelock).with(Puppet[:lastrunfile], 0660)
    @configurer.save_last_run_summary(@report)
  end

  it "should write the raw summary as yaml" do
    @report.expects(:raw_summary).returns("summary")
    @lastrunfd.expects(:print).with(YAML.dump("summary"))
    @configurer.save_last_run_summary(@report)
  end

  it "should log but not fail if saving the last run summary fails" do
    Puppet::Util::FileLocking.expects(:writelock).raises "exception"
    Puppet.expects(:err)
    lambda { @configurer.save_last_run_summary(@report) }.should_not raise_error
  end

end

describe Puppet::Configurer, "when retrieving a catalog" do
  before do
    Puppet.settings.stubs(:use).returns(true)
    @agent = Puppet::Configurer.new
    @agent.stubs(:facts_for_uploading).returns({})

    @catalog = Puppet::Resource::Catalog.new

    # this is the default when using a Configurer instance
    Puppet::Resource::Catalog.indirection.stubs(:terminus_class).returns :rest

    @agent.stubs(:convert_catalog).returns @catalog
  end

  describe "and configured to only retrieve a catalog from the cache" do
    before do
      Puppet.settings[:use_cached_catalog] = true
    end

    it "should first look in the cache for a catalog" do
      Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_terminus] == true }.returns @catalog
      Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.never

      @agent.retrieve_catalog.should == @catalog
    end

    it "should compile a new catalog if none is found in the cache" do
      Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_terminus] == true }.returns nil
      Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.returns @catalog

      @agent.retrieve_catalog.should == @catalog
    end
  end

  describe "when not using a REST terminus for catalogs" do
    it "should not pass any facts when retrieving the catalog" do
      @agent.expects(:facts_for_uploading).never
      Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options|
        options[:facts].nil?
      }.returns @catalog

      @agent.retrieve_catalog
    end
  end

  describe "when using a REST terminus for catalogs" do
    it "should pass the prepared facts and the facts format as arguments when retrieving the catalog" do
      @agent.expects(:facts_for_uploading).returns(:facts => "myfacts", :facts_format => :foo)
      Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options|
        options[:facts] == "myfacts" and options[:facts_format] == :foo
      }.returns @catalog

      @agent.retrieve_catalog
    end
  end

  it "should use the Catalog class to get its catalog" do
    Puppet::Resource::Catalog.indirection.expects(:find).returns @catalog

    @agent.retrieve_catalog
  end

  it "should use its certname to retrieve the catalog" do
    Facter.stubs(:value).returns "eh"
    Puppet.settings[:certname] = "myhost.domain.com"
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| name == "myhost.domain.com" }.returns @catalog

    @agent.retrieve_catalog
  end

  it "should default to returning a catalog retrieved directly from the server, skipping the cache" do
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.returns @catalog

    @agent.retrieve_catalog.should == @catalog
  end

  it "should log and return the cached catalog when no catalog can be retrieved from the server" do
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.returns nil
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_terminus] == true }.returns @catalog

    Puppet.expects(:notice)

    @agent.retrieve_catalog.should == @catalog
  end

  it "should not look in the cache for a catalog if one is returned from the server" do
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.returns @catalog
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_terminus] == true }.never

    @agent.retrieve_catalog.should == @catalog
  end

  it "should return the cached catalog when retrieving the remote catalog throws an exception" do
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.raises "eh"
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_terminus] == true }.returns @catalog

    @agent.retrieve_catalog.should == @catalog
  end

  it "should log and return nil if no catalog can be retrieved from the server and :usecacheonfailure is disabled" do
    Puppet.stubs(:[])
    Puppet.expects(:[]).with(:usecacheonfailure).returns false
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.returns nil

    Puppet.expects(:warning)

    @agent.retrieve_catalog.should be_nil
  end

  it "should return nil if no cached catalog is available and no catalog can be retrieved from the server" do
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_cache] == true }.returns nil
    Puppet::Resource::Catalog.indirection.expects(:find).with { |name, options| options[:ignore_terminus] == true }.returns nil

    @agent.retrieve_catalog.should be_nil
  end

  it "should convert the catalog before returning" do
    Puppet::Resource::Catalog.indirection.stubs(:find).returns @catalog

    @agent.expects(:convert_catalog).with { |cat, dur| cat == @catalog }.returns "converted catalog"
    @agent.retrieve_catalog.should == "converted catalog"
  end

  it "should return nil if there is an error while retrieving the catalog" do
    Puppet::Resource::Catalog.indirection.expects(:find).at_least_once.raises "eh"

    @agent.retrieve_catalog.should be_nil
  end
end

describe Puppet::Configurer, "when converting the catalog" do
  before do
    Puppet.settings.stubs(:use).returns(true)
    @agent = Puppet::Configurer.new

    @catalog = Puppet::Resource::Catalog.new
    @oldcatalog = stub 'old_catalog', :to_ral => @catalog
  end

  it "should convert the catalog to a RAL-formed catalog" do
    @oldcatalog.expects(:to_ral).returns @catalog

    @agent.convert_catalog(@oldcatalog, 10).should equal(@catalog)
  end

  it "should finalize the catalog" do
    @catalog.expects(:finalize)

    @agent.convert_catalog(@oldcatalog, 10)
  end

  it "should record the passed retrieval time with the RAL catalog" do
    @catalog.expects(:retrieval_duration=).with 10

    @agent.convert_catalog(@oldcatalog, 10)
  end

  it "should write the RAL catalog's class file" do
    @catalog.expects(:write_class_file)

    @agent.convert_catalog(@oldcatalog, 10)
  end
end

describe Puppet::Configurer, "when preparing for a run" do
  before do
    Puppet.settings.stubs(:use).returns(true)
    @agent = Puppet::Configurer.new
    @agent.stubs(:dostorage)
    @agent.stubs(:download_fact_plugins)
    @agent.stubs(:download_plugins)
    @agent.stubs(:execute_prerun_command)
    @facts = {"one" => "two", "three" => "four"}
  end

  it "should initialize the metadata store" do
    @agent.class.stubs(:facts).returns(@facts)
    @agent.expects(:dostorage)
    @agent.prepare({})
  end

  it "should download fact plugins" do
    @agent.expects(:download_fact_plugins)

    @agent.prepare({})
  end

  it "should download plugins" do
    @agent.expects(:download_plugins)

    @agent.prepare({})
  end

  it "should perform the pre-run commands" do
    @agent.expects(:execute_prerun_command)
    @agent.prepare({})
  end
end
