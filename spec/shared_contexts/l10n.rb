require 'spec_helper'

# include this context in order to test i18n/l10n
RSpec.shared_context('l10n') do |locale|
  before :all do
    @old_locale = Locale.current
    Locale.current = locale
    Puppet::GettextConfig.setup_locale

    # overwrite stubs with real implementation
    ::Object.remove_method(:_)
    class ::Object
      include FastGettext::Translation
    end
  end

  after :all do
    Locale.current = @old_locale

    # restore stubs
    load File.expand_path(File.join(__dir__, '../../lib/puppet/gettext/stubs.rb'))
  end

  before :each do
    Puppet[:disable_i18n] = false
  end
end
