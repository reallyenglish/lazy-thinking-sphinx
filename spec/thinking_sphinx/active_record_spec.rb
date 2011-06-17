require 'spec_helper'

describe ThinkingSphinx::ActiveRecord do
  before :each do
    @existing_alpha_indexes = Alpha.sphinx_indexes.clone
    @existing_beta_indexes  = Beta.sphinx_indexes.clone
    
    Alpha.send :defined_indexes=, false
    Beta.send  :defined_indexes=, false
    
    Alpha.sphinx_indexes.clear
    Beta.sphinx_indexes.clear
  end
  
  after :each do
    Alpha.sphinx_indexes.replace @existing_alpha_indexes
    Beta.sphinx_indexes.replace  @existing_beta_indexes
    
    Alpha.send :defined_indexes=, true
    Beta.send  :defined_indexes=, true
    
    Alpha.sphinx_index_blocks.clear
    Beta.sphinx_index_blocks.clear
  end
  
  describe '.define_index' do
    it "should do nothing if indexes are disabled" do
      ThinkingSphinx.define_indexes = false
      ThinkingSphinx::Index.should_not_receive(:new)
      
      Alpha.define_index { }
      Alpha.define_indexes
      
      ThinkingSphinx.define_indexes = true
    end
    
    it "should not evaluate the index block automatically" do
      lambda {
        Alpha.define_index { raise StandardError }
      }.should_not raise_error
    end
    
    it "should add the model to the context collection" do
      Alpha.define_index { indexes :name }
      
      ThinkingSphinx.context.indexed_models.should include("Alpha")
    end
    
    it "should die quietly if there is a database error" do
      ThinkingSphinx::Index::Builder.stub(:generate) { raise Mysql::Error }
      Alpha.define_index { indexes :name }
      
      lambda {
        Alpha.define_indexes
      }.should_not raise_error
    end
    
    it "should die noisily if there is a non-database error" do
      ThinkingSphinx::Index::Builder.stub(:generate) { raise StandardError }
      Alpha.define_index { indexes :name }
      
      lambda {
        Alpha.define_indexes
      }.should raise_error
    end
    
    it "should set the index's name using the parameter if provided" do
      Alpha.define_index('custom') { indexes :name }
      Alpha.define_indexes
      
      Alpha.sphinx_indexes.first.name.should == 'custom'
    end
    
    context 'callbacks' do
      it "should add a before_validation callback to define_indexes" do
        Alpha.should_receive(:before_validation).with(:define_indexes)

        Alpha.define_index { }
      end
      
      it "should not add a before_validation callback twice" do
        Alpha.should_receive(:before_validation).with(:define_indexes).once

        Alpha.define_index { }
        Alpha.define_index { }
      end

      it "should add a before_destroy callback to define_indexes" do
        Alpha.should_receive(:before_destroy).with(:define_indexes)

        Alpha.define_index { }
      end
      
      it "should not add a before_destroy callback twice" do
        Alpha.should_receive(:before_destroy).with(:define_indexes).once

        Alpha.define_index { }
        Alpha.define_index { }
      end
    end
  end
  
  describe '.source_of_sphinx_index' do
    it "should return self if model defines an index" do
      Person.source_of_sphinx_index.should == Person
    end

    it "should return the parent if model inherits an index" do
      Admin::Person.source_of_sphinx_index.should == Person
    end
  end
  
  describe '.to_crc32' do
    it "should return an integer" do
      Person.to_crc32.should be_a_kind_of(Integer)
    end
  end
    
  describe '.to_crc32s' do
    it "should return an array" do
      Person.to_crc32s.should be_a_kind_of(Array)
    end
  end
    
  describe "sphinx_indexes in the inheritance chain (STI)" do
    it "should hand defined indexes on a class down to its child classes" do
      Child.sphinx_indexes.should include(*Person.sphinx_indexes)
    end

    it "should allow associations to other STI models" do
      source = Child.sphinx_indexes.last.sources.first
      sql = source.to_riddle_for_core(0, 0).sql_query
      sql.gsub!('$start', '0').gsub!('$end', '100')
      lambda {
        Child.connection.execute(sql)
      }.should_not raise_error(ActiveRecord::StatementInvalid)
    end
  end
  
  describe '#sphinx_document_id' do
    before :each do
      Alpha.define_index { indexes :name }
      Beta.define_index  { indexes :name }
    end
    
    it "should return values with the expected offset" do
      person      = Person.find(:first)
      model_count = ThinkingSphinx.context.indexed_models.length
      Person.stub!(:sphinx_offset => 3)
      
      (person.id * model_count + 3).should == person.sphinx_document_id
    end
  end
  
  describe '#primary_key_for_sphinx' do
    before :each do
      @person = Person.find(:first)
    end
    
    after :each do
      Person.clear_primary_key_for_sphinx
    end
    
    after :each do
      Person.set_sphinx_primary_key nil
    end
    
    it "should return the id by default" do
      @person.primary_key_for_sphinx.should == @person.id
    end
    
    it "should use the sphinx primary key to determine the value" do
      Person.set_sphinx_primary_key :first_name
      @person.primary_key_for_sphinx.should == @person.first_name
    end
    
    it "should not use accessor methods but the attributes hash" do
      id = @person.id
      @person.stub!(:id => 'unique_hash')
      @person.primary_key_for_sphinx.should == id
    end
    
    it "should be inherited by subclasses" do
      Person.set_sphinx_primary_key :first_name
      Parent.superclass.custom_primary_key_for_sphinx?
      Parent.primary_key_for_sphinx.should == Person.primary_key_for_sphinx
    end
  end
  
  describe '.sphinx_index_names' do
    it "should return the core index" do
      Alpha.define_index { indexes :name }
      Alpha.define_indexes
      Alpha.sphinx_index_names.should == ['alpha_core']
    end
    
    it "should return the superclass with an index definition" do
      Parent.sphinx_index_names.should == ['person_core']
    end
  end
  
  describe '.indexed_by_sphinx?' do
    it "should return true if there is at least one index on the model" do
      Alpha.define_index { indexes :name }
      Alpha.define_indexes
      
      Alpha.should be_indexed_by_sphinx
    end
    
    it "should return false if there are no indexes on the model" do
      Gamma.should_not be_indexed_by_sphinx
    end
  end
  
  describe '.delete_in_index' do
    before :each do
      @client = stub('client')
      ThinkingSphinx.stub!(:sphinx_running? => true)
      ThinkingSphinx::Configuration.instance.stub!(:client => @client)
      Alpha.stub!(:search_for_id => true)
    end
    
    it "should not update if the document isn't in the given index" do
      Alpha.stub!(:search_for_id => false)
      @client.should_not_receive(:update)
      
      Alpha.delete_in_index('alpha_core', 42)
    end
    
    it "should direct the update to the supplied index" do
      @client.should_receive(:update) do |index, attributes, values|
        index.should == 'custom_index_core'
      end
      
      Alpha.delete_in_index('custom_index_core', 42)
    end
    
    it "should set the sphinx_deleted flag to true" do
      @client.should_receive(:update) do |index, attributes, values|
        attributes.should == ['sphinx_deleted']
        values.should == {42 => [1]}
      end
      
      Alpha.delete_in_index('alpha_core', 42)
    end
  end
  
  describe '.core_index_names' do
    it "should return each index's core name" do
      Alpha.define_index('foo') { indexes :name }
      Alpha.define_index('bar') { indexes :name }
      Alpha.define_indexes
      
      Alpha.core_index_names.should == ['foo_core', 'bar_core']
    end
  end
  
  describe '.sphinx_offset' do
    before :each do
      @context = ThinkingSphinx.context
    end
    
    it "should return the index of the model's name in all known indexed models" do
      @context.stub!(:indexed_models => ['Alpha', 'Beta'])
      
      Alpha.sphinx_offset.should == 0
      Beta.sphinx_offset.should  == 1
    end
    
    it "should ignore classes that have indexed superclasses" do
      @context.stub!(:indexed_models => ['Alpha', 'Parent', 'Person'])
      
      Person.sphinx_offset.should == 1
    end
    
    it "should respect first known indexed parents" do
      @context.stub!(:indexed_models => ['Alpha', 'Parent', 'Person'])
      
      Parent.sphinx_offset.should == 1
    end
  end
  
  describe '.has_sphinx_indexes?' do
    it "should return true if there are sphinx indexes defined" do
      Alpha.sphinx_indexes.replace [stub('index')]
      Alpha.sphinx_index_blocks.replace []
      
      Alpha.should have_sphinx_indexes
    end
    
    it "should return true if there are sphinx index blocks defined" do
      Alpha.sphinx_indexes.replace []
      Alpha.sphinx_index_blocks.replace [stub('lambda')]
      
      Alpha.should have_sphinx_indexes
    end
    
    it "should return false if there are no sphinx indexes or blocks" do
      Alpha.sphinx_indexes.clear
      Alpha.sphinx_index_blocks.clear
      
      Alpha.should_not have_sphinx_indexes
    end
  end
  
  describe '.reset_subclasses' do
    it "should reset the stored context" do
      ThinkingSphinx.should_receive(:reset_context!)
      
      ActiveRecord::Base.reset_subclasses
    end
  end
end
