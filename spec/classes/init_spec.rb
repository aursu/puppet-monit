require 'spec_helper'

describe 'monit' do
  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) { facts }

        case facts[:os]['family']
        when 'Debian'
          config_file = '/etc/monit/monitrc'
          config_dir  = '/etc/monit/conf.d'
          monit_version = '5'
          default_file_content = 'START=yes'
          service_hasstatus    = true
        when 'RedHat'
          config_dir        = '/etc/monit.d'
          service_hasstatus = true
          monit_version     = '5'
          config_file = case facts[:os]['name']
                        when 'Amazon'
                          '/etc/monit.conf'
                        else
                          '/etc/monitrc'
                        end
        else
          raise 'unsupported osfamily detected'
        end

        it { is_expected.to compile.with_all_deps }

        it { is_expected.to contain_class('monit') }

        it do
          is_expected.to contain_package('monit').with('ensure' => 'present',
                                                       'provider' => nil)
        end

        it do
          is_expected.to contain_file('/var/lib/monit').with('ensure' => 'directory',
                                                             'owner'  => 'root',
                                                             'group'  => 'root',
                                                             'mode'   => '0755')
        end

        it do
          is_expected.to contain_file('monit_config_dir').with('ensure'  => 'directory',
                                                               'path'    => config_dir,
                                                               'owner'   => 'root',
                                                               'group'   => 'root',
                                                               'mode'    => '0755',
                                                               'purge'   => false,
                                                               'recurse' => false,
                                                               'require' => 'Package[monit]')
        end

        it do
          is_expected.to contain_file('monit_config').with('ensure'  => 'file',
                                                           'path'    => config_file,
                                                           'owner'   => 'root',
                                                           'group'   => 'root',
                                                           'mode'    => '0600',
                                                           'require' => 'Package[monit]')
        end

        monit_config_fixture = if monit_version == '4'
                                 File.read(fixtures("monitrc.4.#{facts[:os]['family']}"))
                               else
                                 File.read(fixtures("monitrc.#{facts[:os]['family']}"))
                               end

        it { is_expected.to contain_file('monit_config').with_content(monit_config_fixture) }

        if facts[:os]['family'] == 'Debian'
          it do
            is_expected.to contain_file('/etc/default/monit').with('notify' => 'Service[monit]').
              with_content(%r{^#{default_file_content}$})
          end
        else
          it { is_expected.not_to contain_file('/etc/default/monit') }
        end

        it do
          is_expected.to contain_service('monit').with('ensure'     => 'running',
                                                       'name'       => 'monit',
                                                       'enable'     => true,
                                                       'hasrestart' => true,
                                                       'hasstatus'  => service_hasstatus,
                                                       'subscribe'  => [
                                                         'File[/var/lib/monit]',
                                                         'File[monit_config_dir]',
                                                         'File[monit_config]',
                                                       ])
        end

        describe 'parameter functionality' do
          context 'when check_interval is set to valid integer <242>' do
            let(:params) { { check_interval: 242 } }

            it { is_expected.to contain_file('monit_config').with_content(%r{^set daemon 242$}) }
          end

          context 'when httpd is set to valid bool <true>' do
            let(:params) { { httpd: true } }

            content = <<~END
              set httpd port 2812 and
                 use address localhost
                 allow 0.0.0.0/0.0.0.0
                 allow admin:monit
            END
            it { is_expected.to contain_file('monit_config').with_content(%r{#{content}}) }
          end

          context 'when httpd_* params are set to valid values' do
            let(:params) do
              {
                httpd:          true,
                httpd_port:     2420,
                httpd_address:  'otherhost',
                httpd_allow:    '0.0.0.0/0.0.0.0',
                httpd_user:     'tester',
                httpd_password: 'Passw0rd',
              }
            end

            content = <<~END
              set httpd port 2420 and
                 use address otherhost
                 allow 0.0.0.0/0.0.0.0
                 allow tester:Passw0rd
            END
            it { is_expected.to contain_file('monit_config').with_content(%r{#{content}}) }
          end

          context 'when httpd_password parameter consists special charaters' do
            let(:params) do
              {
                httpd:          true,
                httpd_port:     2420,
                httpd_address:  'otherhost',
                httpd_allow:    '0.0.0.0/0.0.0.0',
                httpd_user:     'tester',
                httpd_password: 'Pa$$w0rd',
              }
            end

            it { is_expected.to contain_file('monit_config').with_content(%r{^\s+allow tester:"Pa\$\$w0rd"$}) }
          end

          context 'when manage_firewall and http are set to valid bool <true>' do
            let(:pre_condition) { ['include ::firewall'] }
            let(:facts) { facts.merge(iptables_persistent_version: '0.5.3ubuntu2') }
            let(:params) do
              {
                manage_firewall: true,
                httpd: true,
              }
            end

            it do
              is_expected.to contain_firewall('2812 allow Monit inbound traffic').with('jump' => 'accept',
                                                                                       'dport' => '2812',
                                                                                       'proto' => 'tcp')
            end
          end

          context 'when package_ensure is set to valid string <absent>' do
            let(:params) { { package_ensure: 'absent' } }

            it { is_expected.to contain_package('monit').with_ensure('absent') }
          end

          context 'when package_name is set to valid string <monit3>' do
            let(:params) { { package_name: 'monit3' } }

            it { is_expected.to contain_package('monit').with_name('monit3') }
          end

          context 'when service_enable is set to valid bool <false>' do
            let(:params) { { service_enable: false } }

            it { is_expected.to contain_service('monit').with_enable(false) }
          end

          context 'when service_ensure is set to valid string <stopped>' do
            let(:params) { { service_ensure: 'stopped' } }

            it { is_expected.to contain_service('monit').with_ensure('stopped') }
          end

          context 'when service_manage is set to valid bool <false>' do
            let(:params) { { service_manage: false } }

            it { is_expected.not_to contain_service('monit') }
            it { is_expected.not_to contain_file('/etc/default/monit') }
          end

          context 'when service_name is set to valid string <stopped>' do
            let(:params) { { service_name: 'monit3' } }

            it { is_expected.to contain_service('monit').with_name('monit3') }
          end

          context 'when logfile is set to valid path </var/log/monit3.log>' do
            let(:params) { { logfile: '/var/log/monit3.log' } }

            it { is_expected.to contain_file('monit_config').with_content(%r{^set logfile /var/log/monit3.log$}) }
          end

          context 'when logfile is set to valid string <syslog>' do
            let(:params) { { logfile: 'syslog' } }

            it { is_expected.to contain_file('monit_config').with_content(%r{^set logfile syslog$}) }
          end

          context 'when mailserver is set to valid string <mailhost>' do
            let(:params) { { mailserver: 'mailhost' } }

            it { is_expected.to contain_file('monit_config').with_content(%r{^set mailserver mailhost$}) }
          end

          context 'when mailformat is set to valid hash' do
            let(:params) do
              {
                mailformat: {
                  'from'    => 'monit@test.local',
                  'message' => 'Monit $ACTION $SERVICE at $DATE on $HOST: $DESCRIPTION',
                  'subject' => 'spectesting',
                },
              }
            end

            content = <<~END
              set mail-format {
                  from: monit@test.local
                  message: Monit $ACTION $SERVICE at $DATE on $HOST: $DESCRIPTION
                  subject: spectesting
              }
            END
            it { is_expected.to contain_file('monit_config').with_content(%r{#{Regexp.escape(content)}}) }
          end

          context 'when alert_emails is set to valid array' do
            let(:params) do
              {
                alert_emails: [
                  'spec@test.local',
                  'tester@test.local',
                ],
              }
            end

            content = <<~END
              set alert spec@test.local
              set alert tester@test.local
            END
            it { is_expected.to contain_file('monit_config').with_content(%r{#{content}}) }
          end

          context 'when mmonit_address is set to valid string <monit3.test.local>' do
            let(:params) { { mmonit_address: 'monit3.test.local' } }

            content = 'set mmonit https://monit:monit@monit3.test.local:8443/collector'
            it { is_expected.to contain_file('monit_config').with_content(%r{#{content}}) }
          end

          context 'when mmonit_without_credential is set to valid bool <true>' do
            let(:params) do
              {
                mmonit_without_credential: true,
                mmonit_address: 'monit3.test.local',
              }
            end

            content = '   and register without credentials'
            it { is_expected.to contain_file('monit_config').with_content(%r{#{content}}) }
          end

          context 'when mmonit_* params are set to valid values' do
            let(:params) do
              {
                mmonit_address:  'monit242.test.local',
                mmonit_https:    false,
                mmonit_port:     8242,
                mmonit_user:     'monituser',
                mmonit_password: 'Pa55w0rd',
              }
            end

            content = 'set mmonit http://monituser:Pa55w0rd@monit242.test.local:8242/collector'
            it { is_expected.to contain_file('monit_config').with_content(%r{#{content}}) }
          end

          context 'when config_file is set to valid path </etc/monit3.conf>' do
            let(:params) { { config_file: '/etc/monit3.conf' } }

            it { is_expected.to contain_file('monit_config').with_path('/etc/monit3.conf') }
          end

          context 'when config_dir is set to valid path </etc/monit3/conf.d>' do
            let(:params) { { config_dir: '/etc/monit3/conf.d' } }

            it { is_expected.to contain_file('monit_config_dir').with_path('/etc/monit3/conf.d') }
          end

          context 'when config_dir_purge is set to valid bool <true>' do
            let(:params) { { config_dir_purge: true } }

            it do
              is_expected.to contain_file('monit_config_dir').with('purge' => true,
                                                                   'recurse' => true)
            end
          end
        end
      end
    end
  end

  describe 'failures' do
    let(:facts) do
      {
        os: {
          'family' => 'Debian',
          'distro' => {
            'codename' => 'buster'
          },
        },
        osfamily:        'Debian',
        lsbdistcodename: 'buster',
        monit_version:   '5',
      }
    end

    [-1, 65_536].each do |value|
      context "when httpd_port is set to invalid value <#{value}>" do
        let(:params) do
          {
            httpd:          true,
            httpd_port:     value,
            httpd_address:  'otherhost',
            httpd_user:     'tester',
            httpd_password: 'Passw0rd',
          }
        end

        it 'fails' do
          expect {
            is_expected.to contain_class('monit')
          }.to raise_error(Puppet::PreformattedError, %r{expects an Integer\[1, 65535\] value})
        end
      end
    end

    context 'when check_interval is set to invalid value <0>' do
      let(:params) { { check_interval: 0 } }

      it 'fails' do
        expect {
          is_expected.to contain_class('monit')
        }.to raise_error(Puppet::PreformattedError, %r{expects an Integer\[1})
      end
    end

    context 'when start_delay is set to invalid value <0>' do
      let(:params) { { start_delay: 0 } }

      it 'fails' do
        expect {
          is_expected.to contain_class('monit')
        }.to raise_error(Puppet::PreformattedError, %r{expects a value of type Undef or Integer\[1})
      end
    end

    context 'when major release of EL is unsupported' do
      let :facts do
        { os: {
            'family' => 'RedHat',
            'name' => 'CentOS',
            'release' => {
              'major' => '6'
            },
          },
          osfamily:                  'RedHat',
          operatingsystem:           'CentOS',
          operatingsystemmajrelease: '6',
          monit_version:             '5' }
      end

      it 'fails' do
        expect {
          is_expected.to contain_class('monit')
        }.to raise_error(Puppet::Error, %r{monit supports EL 7, 8 and 9\. Detected operatingsystemmajrelease is <6>\.})
      end
    end

    context 'when major release of Debian is unsupported' do
      let :facts do
        { os: {
            'family' => 'Debian',
            'distro' => {
              'codename' => 'etch'
            },
            'release' => {
              'major' => '4'
            },
          },
          osfamily:                  'Debian',
          operatingsystemmajrelease: '4',
          lsbdistcodename:           'etch',
          monit_version:             '5' }
      end

      it 'fails' do
        expect {
          is_expected.to contain_class('monit')
        }.to raise_error(Puppet::Error, %r{monit supports Debian 10 \(buster\), 11 \(bullseye\) and 12 \(bookworm\) and \
Ubuntu 18\.04 \(bionic\), 20\.04 \(focal\) and 22\.04 \(jammy\)\. Detected lsbdistcodename is <etch>\.})
      end
    end

    context 'when major release of Ubuntu is unsupported' do
      let :facts do
        { os: {
            'family' => 'Debian',
            'distro' => {
              'codename' => 'xenial'
            },
            'release' => {
              'major' => '16.04'
            },
          },
          osfamily:                  'Debian',
          operatingsystemmajrelease: '16.04',
          lsbdistcodename:           'xenial',
          monit_version:             '5' }
      end

      it 'fails' do
        expect {
          is_expected.to contain_class('monit')
        }.to raise_error(Puppet::Error, %r{monit supports Debian 10 \(buster\), 11 \(bullseye\) and 12 \(bookworm\) and \
Ubuntu 18\.04 \(bionic\), 20\.04 \(focal\) and 22\.04 \(jammy\)\. Detected lsbdistcodename is <xenial>\.})
      end
    end

    context 'when osfamily is unsupported' do
      let :facts do
        { os: {
            'family' => 'Unsupported',
            'release' => {
              'major' => '9'
            },
          },
          osfamily:                  'Unsupported',
          operatingsystemmajrelease: '9',
          monit_version:             '5' }
      end

      it 'fails' do
        expect {
          is_expected.to contain_class('monit')
        }.to raise_error(Puppet::Error, %r{monit supports osfamilies Debian and RedHat\. Detected osfamily is <Unsupported>\.})
      end
    end
  end

  describe 'variable type and content validations' do
    # set needed custom facts and variables
    let(:facts) do
      {
        os: {
          'family' => 'Debian',
          'distro' => {
            'codename' => 'buster'
          },
          'release' => {
            'full'  => '10.0',
            'major' => '10'
          },
        },
        osfamily:                  'Debian',
        operatingsystemrelease:    '10.0',
        operatingsystemmajrelease: '10',
        lsbdistcodename:           'buster',
        monit_version:             '5',
      }
    end
    let(:validation_params) do
      {}
    end

    validations = {
      'absolute_path' => {
        name: ['config_file', 'config_dir'],
        valid: ['/absolute/filepath', '/absolute/directory/'],
        invalid: ['invalid', 3, 2.42, ['array'], { 'ha' => 'sh' }],
        message: '(expects a String value|is not an absolute path)',
      },
      'array' => {
        name: ['alert_emails'],
        valid: [['valid', 'array']],
        invalid: ['string', { 'ha' => 'sh' }, 3, 2.42, true],
        message: 'expects an Array value',
      },
      'bool_stringified' => {
        name: ['httpd', 'manage_firewall', 'service_enable', 'service_manage', 'mmonit_https', 'mmonit_without_credential', 'config_dir_purge'],
        valid: [true, 'true', false, 'false'],
        invalid: ['invalid', 3, 2.42, ['array'], { 'ha' => 'sh' }, nil],
        message: 'expects a value of type Boolean or Enum',
      },
      'integer' => {
        name: ['check_interval', 'httpd_port', 'mmonit_port'],
        valid: [242],
        invalid: [2.42, 'invalid', ['array'], { 'ha' => 'sh ' }, true, false, nil],
        message: 'expects an Integer',
      },
      'optional_integer' => {
        name: ['start_delay'],
        valid: [242],
        invalid: [2.42, 'invalid', ['array'], { 'ha' => 'sh ' }, true, false, nil],
        message: 'expects a value of type Undef or Integer',
      },
      'optional_logfile' => {
        name: ['logfile'],
        valid: ['/absolute/filepath', '/absolute/directory/', 'syslog', 'syslog facility log_local0'],
        invalid: ['invalid', 3, 2.42, ['array'], { 'ha' => 'sh' }],
        message: '(expects a value of type Undef or String|is not an absolute path)',
      },
      'optional_hash' => {
        name: ['mailformat'],
        valid: [{ 'ha' => 'sh' }],
        invalid: ['string', 3, 2.42, ['array'], true, false, nil],
        message: 'expects a value of type Undef or Hash',
      },
      'optional_string' => {
        name: ['mailserver', 'mmonit_address'],
        valid: ['present'],
        invalid: [['array'], { 'ha' => 'sh' }],
        message: 'expects a value of type Undef or String',
      },
      'string' => {
        name: ['httpd_address', 'httpd_allow', 'httpd_user', 'httpd_password',
               'package_ensure', 'package_name', 'service_name', 'mmonit_user',
               'mmonit_password'],
        valid: ['present'],
        invalid: [['array'], { 'ha' => 'sh' }],
        message: 'expects a String value',
      },
      'service_ensure_string' => {
        name: ['service_ensure'],
        valid: ['running'],
        invalid: [['array'], { 'ha' => 'sh' }],
        message: 'expects a match for Enum\[\'running\', \'stopped\'\]',
      },
    }

    validations.sort.each do |type, var|
      var[:name].each do |var_name|
        var[:valid].each do |valid|
          context "with #{var_name} (#{type}) set to valid #{valid} (as #{valid.class})" do
            let(:params) { validation_params.merge("#{var_name}": valid) }

            it { is_expected.to compile }
          end
        end

        var[:invalid].each do |invalid|
          context "with #{var_name} (#{type}) set to invalid #{invalid} (as #{invalid.class})" do
            let(:params) { validation_params.merge("#{var_name}": invalid) }

            it 'fails' do
              expect {
                catalogue
              }.to raise_error # (Puppet::Error, %r{#{var[:message]}})
            end
          end
        end
      end # var[:name].each
    end # validations.sort.each
  end # describe 'variable type and content validations'
end
