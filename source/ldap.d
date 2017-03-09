module ldap;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import std.utf;

class LDAPException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc @safe
	{
		super(msg, file, line);
	}
}

version (Windows)
{
	public import core.sys.windows.winldap;
	public import core.sys.windows.winber;

	private enum LDAPErrorCodes
	{ // Taken from core.sys.windows.winldap
		LDAP_SUCCESS = 0x00,
		LDAP_OPT_SUCCESS = LDAP_SUCCESS,
		LDAP_OPERATIONS_ERROR,
		LDAP_PROTOCOL_ERROR,
		LDAP_TIMELIMIT_EXCEEDED,
		LDAP_SIZELIMIT_EXCEEDED,
		LDAP_COMPARE_FALSE,
		LDAP_COMPARE_TRUE,
		LDAP_STRONG_AUTH_NOT_SUPPORTED,
		LDAP_AUTH_METHOD_NOT_SUPPORTED = LDAP_STRONG_AUTH_NOT_SUPPORTED,
		LDAP_STRONG_AUTH_REQUIRED,
		LDAP_REFERRAL_V2,
		LDAP_PARTIAL_RESULTS = LDAP_REFERRAL_V2,
		LDAP_REFERRAL,
		LDAP_ADMIN_LIMIT_EXCEEDED,
		LDAP_UNAVAILABLE_CRIT_EXTENSION,
		LDAP_CONFIDENTIALITY_REQUIRED,
		LDAP_SASL_BIND_IN_PROGRESS, // = 0x0e
		LDAP_NO_SUCH_ATTRIBUTE = 0x10,
		LDAP_UNDEFINED_TYPE,
		LDAP_INAPPROPRIATE_MATCHING,
		LDAP_CONSTRAINT_VIOLATION,
		LDAP_TYPE_OR_VALUE_EXISTS,
		LDAP_ATTRIBUTE_OR_VALUE_EXISTS = LDAP_TYPE_OR_VALUE_EXISTS,
		LDAP_INVALID_SYNTAX, // = 0x15
		LDAP_NO_SUCH_OBJECT = 0x20,
		LDAP_ALIAS_PROBLEM,
		LDAP_INVALID_DN_SYNTAX,
		LDAP_IS_LEAF,
		LDAP_ALIAS_DEREF_PROBLEM, // = 0x24
		LDAP_INAPPROPRIATE_AUTH = 0x30,
		LDAP_INVALID_CREDENTIALS,
		LDAP_INSUFFICIENT_ACCESS,
		LDAP_INSUFFICIENT_RIGHTS = LDAP_INSUFFICIENT_ACCESS,
		LDAP_BUSY,
		LDAP_UNAVAILABLE,
		LDAP_UNWILLING_TO_PERFORM,
		LDAP_LOOP_DETECT, // = 0x36
		LDAP_NAMING_VIOLATION = 0x40,
		LDAP_OBJECT_CLASS_VIOLATION,
		LDAP_NOT_ALLOWED_ON_NONLEAF,
		LDAP_NOT_ALLOWED_ON_RDN,
		LDAP_ALREADY_EXISTS,
		LDAP_NO_OBJECT_CLASS_MODS,
		LDAP_RESULTS_TOO_LARGE,
		LDAP_AFFECTS_MULTIPLE_DSAS, // = 0x47
		LDAP_OTHER = 0x50,
		LDAP_SERVER_DOWN,
		LDAP_LOCAL_ERROR,
		LDAP_ENCODING_ERROR,
		LDAP_DECODING_ERROR,
		LDAP_TIMEOUT,
		LDAP_AUTH_UNKNOWN,
		LDAP_FILTER_ERROR,
		LDAP_USER_CANCELLED,
		LDAP_PARAM_ERROR,
		LDAP_NO_MEMORY,
		LDAP_CONNECT_ERROR,
		LDAP_NOT_SUPPORTED,
		LDAP_CONTROL_NOT_FOUND,
		LDAP_NO_RESULTS_RETURNED,
		LDAP_MORE_RESULTS_TO_RETURN,
		LDAP_CLIENT_LOOP,
		LDAP_REFERRAL_LIMIT_EXCEEDED // = 0x61
	}

	string ldapWinErrorToString(uint err) pure nothrow @safe
	{
		try
		{
			return (cast(LDAPErrorCodes) err).to!string;
		}
		catch (Exception)
		{
			return err.to!string;
		}
	}

	class LDAPConnectionException : LDAPException
	{
		this(string host, uint errCode, string file = __FILE__, size_t line = __LINE__)
		{
			super("Failed to connect to " ~ host ~ ": " ~ errCode.ldap_err2string.to!string ~ " (Error code "
					~ errCode.to!string ~ ", " ~ errCode.ldapWinErrorToString ~ ")", file, line);
		}
	}

	pragma(inline, true) auto enforceLDAP(string fn, string file = __FILE__, size_t line = __LINE__)(
			lazy uint f)
	{
		auto ret = f();
		if (ret != LDAP_SUCCESS)
			throw new LDAPException("LDAP Error '" ~ ret.ldap_err2string.to!string ~ "' in " ~ fn
					~ " (Error code " ~ ret.to!string ~ ", " ~ ret.ldapWinErrorToString ~ ")",
					file, line);
	}

	enum LDAP_OPT_FAST_CONCURRENT_BIND = 0x41;

	extern (C) uint ldap_search_ext_sW(LDAP*, wchar*, uint, wchar*, wchar**,
			uint, PLDAPControlW*, PLDAPControlW*, LDAP_TIMEVAL*, uint, LDAPMessage**);

	alias mPLDAPControl = PLDAPControlW;

	PLDAP ldapInit(string host)
	{
		return ldap_initW(cast(wchar*) host.toUTF16z, 389);
	}

	uint ldapBind(PLDAP _handle, string user, string cred, int method)
	{
		return ldap_bind_sW(_handle, cast(wchar*) user.toUTF16z,
				cast(wchar*) cred.toUTF16z, method);
	}
}
else
{
	import core.sys.posix.sys.time;

	struct berval
	{
		int bv_len;
		char* bv_val;
	}

	alias BerValue = berval;
	struct ldapcontrol
	{
		char* ldctl_oid; /* numericoid of control */
		berval ldctl_value; /* encoded value of control */
		char ldctl_iscritical; /* criticality */
	};
	alias LDAPControl = ldapcontrol;
	alias mPLDAPControl = LDAPControl*;

	alias PLDAPMessage = void*;
	alias PLDAP = void*;

	extern (C) void ldap_msgfree(void*);
	extern (C) void ldap_memfree(void*);
	extern (C) void ber_free(void*, int);
	extern (C) void ldap_value_free(char**);

	extern (C) int ldap_get_option(void* ld, int option, void* outvalue);
	extern (C) int ldap_set_option(void* ld, int option, const void* invalue);

	extern (C) int ldap_initialize(void**, const char*);
	extern (C) char* ldap_err2string(int);
	extern (C) void* ldap_first_entry(void* ld, void* chain);
	extern (C) void* ldap_next_entry(void* ld, void* entry);
	extern (C) char* ldap_get_dn(void* ld, void* entry);
	extern (C) int ldap_search_ext_s(void* ld, const char* base, int _scope, const char* filter,
			char** attrs, int attrsonly, LDAPControl** serverctrls,
			LDAPControl** clientctrls, timeval* timeout, int sizelimit, void** res); // LDAPMessage
	extern (C) char* ldap_first_attribute(void* ld, void* entry, void** ber);
	extern (C) char* ldap_next_attribute(void* ld, void* entry, void* ber);
	extern (C) char** ldap_get_values(void* ld, void* entry, char* attr);
	extern (C) int ldap_count_entries(PLDAP, void*);
	extern (C) int ldap_count_values(char**);

	extern (C) int ldap_bind_s(void* ld, const char* who, const char* cred, int method);
	extern (C) int ldap_unbind(void* ld);
	alias ldap_unbind_s = ldap_unbind;

	enum LDAP_SCOPE_BASE = 0x0000, LDAP_SCOPE_BASEOBJECT = LDAP_SCOPE_BASE,
			LDAP_SCOPE_ONELEVEL = 0x0001, LDAP_SCOPE_ONE = LDAP_SCOPE_ONELEVEL,
			LDAP_SCOPE_SUBTREE = 0x0002,
			LDAP_SCOPE_SUB = LDAP_SCOPE_SUBTREE, LDAP_SCOPE_SUBORDINATE = 0x0003, /* OpenLDAP extension */
			LDAP_SCOPE_CHILDREN = LDAP_SCOPE_SUBORDINATE, LDAP_SCOPE_DEFAULT = -1; /* OpenLDAP extension */

	enum LDAP_SUCCESS = 0;
	enum LDAP_AUTH_SIMPLE = 0x80U;
	enum void* LDAP_OPT_OFF = null, LDAP_OPT_ON = cast(void*) 1;

	enum LDAP_OPT_PROTOCOL_VERSION = 0x0011U;
	enum LDAP_OPT_FAST_CONCURRENT_BIND = 0x41;
	alias PLDAP_TIMEVAL = timeval*;

	class LDAPConnectionException : LDAPException
	{
		this(string host, uint errCode, string file = __FILE__, size_t line = __LINE__)
		{
			super("Failed to connect to " ~ host ~ ": " ~ errCode.ldap_err2string.to!string
					~ " (Error code " ~ errCode.to!string ~ ")", file, line);
		}
	}

	pragma(inline, true) auto enforceLDAP(string fn, string file = __FILE__, size_t line = __LINE__)(
			lazy uint f)
	{
		auto ret = f();
		if (ret != LDAP_SUCCESS)
			throw new LDAPException("LDAP Error '" ~ ret.ldap_err2string.to!string
					~ "' in " ~ fn ~ " (Error code " ~ ret.to!string ~ ")", file, line);
	}

	PLDAP ldapInit(string host)
	{
		void* ret;
		enforceLDAP!"initialize"(ldap_initialize(&ret, host.toStringz));
		return ret;
	}

	enum LdapGetLastError = 0;

	uint ldapBind(PLDAP _handle, string user, string cred, int method)
	{
		return ldap_bind_s(_handle, user.toStringz, cred.toStringz, method);
	}
}

struct LDAPConnection
{
	PLDAP _handle;

	/// Connects to the LDAP server using the given host.
	/// Params:
	///     host: Host name and port separated with a colon (:)
	this(string host)
	{
		version (Windows)
		{
		}
		else
			host = host.split(' ').map!(a => "ldap://" ~ a).join(' ');
		_handle = ldapInit(host); // The host can contain a port separated with a colon (:) to override this default port
		if (_handle is null)
			throw new LDAPConnectionException(host, LdapGetLastError);
		version (Windows)
			enforceLDAP!"connect"(ldap_connect(_handle, null));
		else
			bind("", "");
	}

	/// Connects to the LDAP server by trying every host until it can find one.
	/// Params:
	///     hosts: List of host names and ports separated with a colon (:)
	this(string[] hosts)
	{
		this(hosts.join(' '));
	}

	~this()
	{
		unbind();
	}

	void unbind()
	{
		ldap_unbind_s(_handle);
	}

	void setOption(int option, void* value)
	{
		enforceLDAP!"setOption"(ldap_set_option(_handle, option, value));
	}

	void getOption(int option, void* value)
	{
		enforceLDAP!"getOption"(ldap_get_option(_handle, option, value));
	}

	void bind(string user, string cred, int method = LDAP_AUTH_SIMPLE)
	{
		enforceLDAP!"bind"(ldapBind(_handle, user, cred, method));
	}

	SearchResult[] search(string search_base, int search_scope,
			string search_filter = "(objectClass=*)", string[] search_attrs = null,
			int attrsonly = 0, mPLDAPControl serverctrls = null,
			mPLDAPControl clientctrls = null, PLDAP_TIMEVAL timeout = null, int sizelimit = 0)
	{
		PLDAPMessage res;
		scope (failure)
			if (res)
				ldap_msgfree(res);
		version (Windows)
			enforceLDAP!"search"(ldap_search_ext_sW(_handle, cast(wchar*) search_base.toUTF16z, search_scope,
					cast(wchar*) search_filter.toUTF16z, search_attrs is null ? null
					: (search_attrs.map!(a => cast(wchar*) a.toUTF16z).array ~ null).ptr,
					attrsonly, &serverctrls, &clientctrls, timeout, sizelimit, &res));
		else
			enforceLDAP!"search"(ldap_search_ext_s(_handle, cast(char*) search_base.toStringz, search_scope,
					cast(char*) search_filter.toStringz, search_attrs is null ? null
					: (search_attrs.map!(a => cast(char*) a.toStringz).array ~ null).ptr,
					attrsonly, &serverctrls, &clientctrls, timeout, sizelimit, &res));
		SearchResult[] results;
		results.length = cast(size_t) ldap_count_entries(_handle, res);
		PLDAPMessage entry;

		// Would have used ranges, but memory gets corrupted
		foreach (i, ref result; results)
		{
			if (i == 0)
				entry = ldap_first_entry(_handle, res);
			else
				entry = ldap_next_entry(_handle, entry);
			if (entry is null)
				throw new LDAPException("Failed to read entry");

			version (Windows)
			{
				wchar* dn = ldap_get_dnW(_handle, entry);
				if (dn is null)
					throw new LDAPException("Failed to read entry information");
				result.distinguishedName = dn.to!string.idup;
				ldap_memfreeW(dn);
			}
			else
			{
				char* dn = ldap_get_dn(_handle, entry);
				if (dn is null)
					throw new LDAPException("Failed to read entry information");
				result.distinguishedName = dn.to!string.idup;
				ldap_memfree(dn);
			}

			version (Windows)
				BerElement* berP;
			else
				void* berP;
			for (auto attr = ldap_first_attribute(_handle, entry, &berP); attr !is null;
					attr = ldap_next_attribute(_handle, entry, berP))
			{
				string attr_name = attr.to!string;

				auto ppValue = ldap_get_values(_handle, entry, attr);
				if (!ppValue)
				{
					result.attributes[attr_name] = [];
				}
				else
				{
					auto iValue = ldap_count_values(ppValue);
					if (!iValue)
						result.attributes[attr_name] = [];
					else
						result.attributes[attr_name] = ppValue[0 .. iValue].map!(a => a.to!(char[])
								.idup).array;
					ldap_value_free(ppValue);
					ppValue = null;
				}

				ldap_memfree(attr);
			}
			ber_free(berP, 0);
		}
		return results;
	}
}

///
struct SearchResult
{
	/// The path to the entry like `CN=Jeff Smith,OU=Sales,DC=Fabrikam,DC=COM`. See https://msdn.microsoft.com/en-us/library/aa366101(v=vs.85).aspx
	string distinguishedName;
	/// Attributes of this object
	string[][string] attributes;
}

struct LDAPAuthenticationEngine
{
	PLDAP _handle;

	/// Connects to the LDAP server using the given host.
	/// Params:
	///     host: Host name and port separated with a colon (:)
	this(string host)
	{
		version (Windows)
		{
		}
		else
			host = host.split(' ').map!(a => "ldap://" ~ a).join(' ');
		_handle = ldapInit(host); // The host can contain a port separated with a colon (:) to override this default port
		if (_handle is null)
			throw new LDAPConnectionException(host, LdapGetLastError);
		version (Windows)
		{
			enforceLDAP!"connect"(ldap_connect(_handle, null));
			setOption(LDAP_OPT_FAST_CONCURRENT_BIND, LDAP_OPT_ON);
		}
	}

	/// Connects to the LDAP server by trying every host until it can find one.
	/// Params:
	///     hosts: List of host names and ports separated with a colon (:)
	this(string[] hosts)
	{
		this(hosts.join(' '));
	}

	~this()
	{
		unbind();
	}

	void unbind()
	{
		ldap_unbind_s(_handle);
	}

	void setOption(int option, void* value)
	{
		enforceLDAP!"setOption"(ldap_set_option(_handle, option, value));
	}

	void getOption(int option, void* value)
	{
		enforceLDAP!"getOption"(ldap_get_option(_handle, option, value));
	}

	bool check(string user, string cred)
	{
		return ldapBind(_handle, user, cred, LDAP_AUTH_SIMPLE) == LDAP_SUCCESS;
	}
}
