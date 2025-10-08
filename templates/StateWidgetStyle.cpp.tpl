{{COPYRIGHT_HEADER}}

#include "{{HEADER_INCLUDE_PATH}}"

{{CLASS_PREFIX}}{{CLASS_NAME}}::{{CLASS_PREFIX}}{{CLASS_NAME}}()
{
}

{{CLASS_PREFIX}}{{CLASS_NAME}}::~{{CLASS_PREFIX}}{{CLASS_NAME}}()
{
}

const FName {{CLASS_PREFIX}}{{CLASS_NAME}}::TypeName(TEXT("{{CLASS_PREFIX}}{{CLASS_NAME}}"));

const {{CLASS_PREFIX}}{{CLASS_NAME}}& {{CLASS_PREFIX}}{{CLASS_NAME}}::GetDefault()
{
	static {{CLASS_PREFIX}}{{CLASS_NAME}} Default;
	return Default;
}

void {{CLASS_PREFIX}}{{CLASS_NAME}}::GetResources(TArray<const FSlateBrush*>& OutBrushes) const
{
	// Add any brush resources here so that Slate can correctly atlas and reference them
}
