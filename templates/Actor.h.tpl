{{COPYRIGHT_HEADER}}

#pragma once

#include "CoreMinimal.h"
{{DIRECT_INCLUDES}}
#include "{{CLASS_NAME}}.generated.h"


UCLASS({{UCLASS_SPECIFIER}})
class {{API_MACRO}} {{CLASS_PREFIX}}{{CLASS_NAME}} : public {{CLASS_PREFIX}}{{BASE_CLASS_NAME}}
{
	GENERATED_BODY()
	
public:	
	// Sets default values for this actor's properties
	{{CLASS_PREFIX}}{{CLASS_NAME}}();

protected:
	// Called when the game starts or when spawned
	virtual void BeginPlay() override;

public:	
	// Called every frame
	virtual void Tick(float DeltaTime) override;

};
