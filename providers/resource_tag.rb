include AwsCookbook::Ec2

use_inline_resources

def whyrun_supported?
  true
end

action :update do
  resource_id = @new_resource.resource_id || @new_resource.name

  updated_tags = @current_resource.tags.merge(@new_resource.tags)
  if updated_tags.eql?(@current_resource.tags)
    Chef::Log.debug("AWS: Tags for resource #{resource_id} are unchanged")
  else
    # tags that begin with "aws" are reserved
    converge_by("Updating the following tags for resource #{resource_id} (skipping AWS tags): " + updated_tags.inspect) do
      Chef::Log.info("AWS: Updating the following tags for resource #{resource_id} (skipping AWS tags): " + updated_tags.inspect)
      updated_tags.delete_if { |key, _value| key.to_s =~ /^aws/ }
      ec2.create_tags(resources: [resource_id], tags: updated_tags.collect { |k, v| { key: k, value: v } })
    end
  end
end

action :add do
  resource_id = @new_resource.resource_id || @new_resource.name

  @new_resource.tags.each do |k, v|
    if @current_resource.tags.keys.include?(k)
      Chef::Log.debug("AWS: Resource #{resource_id} already has a tag with key '#{k}', will not add tag '#{k}' => '#{v}'")
    else
      converge_by("add tag '#{k}' with value '#{v}' on resource #{resource_id}") do
        ec2.create_tags(resources: [resource_id], tags: [{ key: k, value: v }])
        Chef::Log.info("AWS: Added tag '#{k}' with value '#{v}' on resource #{resource_id}")
      end
    end
  end
end

action :remove do
  resource_id = @new_resource.resource_id || @new_resource.name

  # iterate over the tags specified for deletion
  # delete them if they exist on the node and the values match
  @new_resource.tags.keys.each do |key|
    if @current_resource.tags.keys.include?(key) && @current_resource.tags[key] == @new_resource.tags[key]
      converge_by("delete tag '#{key}' on resource #{resource_id} with value '#{@current_resource.tags[key]}'") do
        ec2.delete_tags(resources: [resource_id], tags: [{ key => @new_resource.tags[key] }])
      end
    else
      Chef::Log.debug("Key #{key} not present on the node or the specified value (#{@new_resource.tags[key]}) does not match the tagged value")
    end
  end
end

action :force_remove do
  resource_id = @new_resource.resource_id || @new_resource.name

  @new_resource.tags.keys do |key|
    if @current_resource.tags.keys.include?(key)
      converge_by("AWS: Deleted tag '#{key}' on resource #{resource_id} with value '#{@current_resource.tags[key]}'") do
        ec2.delete_tags(resources: [resource_id], tags: [{ key: key }])
      end
    else
      Chef::Log.debug("Key #{key} not present on the node. Skipping.")
    end
  end
end

def load_current_resource
  @current_resource = Chef::ResourceResolver.resolve(:aws_resource_tag).new(@new_resource.name)
  @current_resource.name(@new_resource.name)
  if @new_resource.resource_id
    @current_resource.resource_id(@new_resource.resource_id)
  else
    @current_resource.resource_id(@new_resource.name)
  end

  @current_resource.tags({})

  ec2.describe_tags(filters: [{ name: 'resource-id', values: [@current_resource.resource_id] }])[:tags].map do |tag|
    @current_resource.tags[tag[:key]] = tag[:value]
  end

  @current_resource
end
