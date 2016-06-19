require 'exmail/version'
require 'restclient'

module Exmail
  class Server
    attr_accessor :key, :account_name, :access_token
    #主要用于获取token
    DOMAIN_TOKEN = 'exmail.qq.com'
    #主要是调用API
    DOMAIN_API = 'openapi.exmail.qq.com:12211'

    def initialize(account_name, key)
      @account_name, @key=account_name, key
    end

    #获取具体的邮箱的信息
    #返回数据: {"PartyList"=>{"Count"=>1, "List"=>[{"Value"=>"IT部"}]},
    #          "OpenType"=>1, "Name"=>"bruce", "Mobile"=>"18612345678", "Status"=>1, "Tel"=>"",
    #          "Position"=>"IT技术", "Gender"=>1, "SlaveList"=>"", "Alias"=>"bruce.wu@ubox-xzh.com", "ExtId"=>""}
    def user_get(email)
      api_path = '/openapi/user/get'
      result = post_api(api_path, {:alias => email})
      result['error'].nil? ? result : {}
    end

    #检查邮件帐号是否可用,多个邮箱用数组形式传入
    # user_check(['aaa@aaa.com','bbb@bbb.com'])
    # 返回 {"Count"=>2, "List"=>[{"Email"=>"aaa@aaa.com", "Type"=>1}, {"Email"=>"bbb@bbb.com", "Type"=>1}]}
    # Type说明:   -1:帐号名无效 0: 帐号名没被占用  1:主帐号名  2:别名帐号 3:邮件群组帐 号
    def user_check(emails)
      emails=[emails] if emails.class!=Array
      api_path = '/openapi/user/check'
      post_api(api_path, 'email='+emails.join('&email='))
    end

    # 创建用户
    # slave别名列表    # 1. 如果多个别名,传多个 Slave   2. Slave 上限为 5 个   3. Slave 为邮箱格式
    # user_add('bruce.wu@ubox-xzh.com',{:slave=>"", :position=>"", :partypath=>"北京/IT技术部", :gender=>1,
    #           :password=>"123123", :extid=>1, :mobile=>"", :md5=>0, :tel=>"", :name=>"dede", :opentype=>1})
    def user_add(email, user_attr)
      params = user_attr.merge(:action => 2, :alias => email)
      result = user_sync(params)
      if !result.nil? && result['error']=='party_not_found'
        partypath = user_attr[:partypath]||user_attr['partypath']
        party_add_p(partypath)
        sleep(1) #添加完部门要等一会才会有
        user_sync(params)
      end
    end

    # 修改用户,调用方法参考 user_add
    def user_mod(email, user_attr)
      params = user_attr.merge(:action => 3, :alias => email)
      user_sync(params)
    end

    # 修改密码
    # new_pass为新密码
    def change_pass(email, new_pass)
      user_sync({:alias => email, :password => new_pass, :md5 => 0, :action => 3})
    end

    #删除用户
    def user_delete(email)
      user_sync(:action => 1, :alias => email)
    end

    # 同步成员资料
    #Action string 1=DEL, 2=ADD, 3=MOD
    def user_sync(params)
      api_path = '/openapi/user/sync'
      post_api(api_path, params)
    end

    #创建部门
    #多级部门用/分隔,例如:  /IT部/IT产品部
    def party_add(party_name)
      party_sync(:action => 2, :dstpath => party_name)
    end

    # 自动创建所有层的部门
    # 类似于 mkdir_p
    # party_add_p('aa/bb/cc/dd')将创建四级部门
    def party_add_p(party_name)
      _party_path = ''
      party_name.split('/').each do |party|
        next if party.to_s==''
        party_add("#{_party_path}/#{party}") unless party_exists?("#{_party_path}/#{party}")
        _party_path+=('/'+party)
      end
    end

    # 删除部门
    # 多级部门用/分隔,例如:  /IT部/IT产品部
    def party_delete(party_name)
      party_sync(:action => 1, :dstpath => party_name)
    end

    # 修改部门
    # party_mod('/北京','/IT部/IT产品部') 将"/IT部/IT产品部"移动到根目录下,并改名为"北京"
    def party_mod(party_name, parent_party)
      party_sync(:action => 3, :dstpath => party_name, :srcpath => parent_party)
    end

    # 同步部门信息
    def party_sync(params)
      api_path = '/openapi/party/sync'
      post_api(api_path, params)
    end

    #获取子部门
    def party_list(partypath=nil)
      api_path='/openapi/party/list'
      post_api(api_path, {:partypath => partypath})
    end

    # 是否存在该部门
    def party_exists?(party_path)
      result = party_list(party_path)
      result['error']!='party_not_found'
    end

    # 获取部门下成员
    # 获取不存在的部门的子部门返回 {"error"=>"party_not_found", "errcode"=>"1310"}
    # 正常结果 {"Count"=>1, "List"=>[{"Value"=>"北京1"}]}
    def partyuser_list(partypath=nil)
      api_path = '/openapi/partyuser/list'
      post_api(api_path, {:partypath => partypath})
    end

    # 添加邮件群组
    # group-admin==群组管理者(需要使用一个域中不存在的 邮箱地址)
    # status--群组状态(分为 4 类 all,inner,group, list)
    def group_add(group_name, group_admin, status, members)
      api_path='/openapi/group/add'
      post_api(api_path, {:group_name => group_name, :group_admin => group_admin,
                          :status => status, :members => members})
    end

    # 删除邮件群组
    # group_alias--群组管理员(一个域中不存在的邮箱地址)
    def group_delete(group_alias)
      api_path='/openapi/group/delete'
      post_api(api_path, {:group_alias => group_alias})
    end

    # 添加邮件群组成员
    def group_add_member(group_alias, members)
      api_path = '/openapi/group/addmember'
      post_api(api_path, {:group_alias => group_alias, :members => members})
    end

    # 删除邮件群组成员
    def group_del_member(group_alias, members)
      api_path = '/openapi/group/deletemember'
      post_api(api_path, {:group_alias => group_alias, :members => members})
    end

    #返回数据: {access_token":"", "token_type":"Bearer", "expires_in":86400, "refresh_token":""}
    def get_token
      url_path = '/cgi-bin/token'
      url = "https://#{DOMAIN_TOKEN}#{url_path}"
      json_str = RestClient.post(url, {:grant_type => 'client_credentials',
                                       :client_id => @account_name,
                                       :client_secret => @key})
      json = JSON.load(json_str)
      @access_token = json['access_token']
      json
    end

    def post_api(api_path, params)
      get_token if @access_token.nil?
      url = "http://#{DOMAIN_API}#{api_path}"
      JSON.load RestClient.post(url, params, {:Authorization => "Bearer #{@access_token}"})
    end
  end
end
